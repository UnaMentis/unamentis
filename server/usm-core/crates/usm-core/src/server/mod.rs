//! HTTP/WebSocket server for real-time service management

use std::sync::Arc;

use anyhow::Result;
use axum::{
    extract::{Path, Query, State, WebSocketUpgrade},
    http::StatusCode,
    response::{IntoResponse, Json},
    routing::{get, post},
    Router,
};
use serde::Deserialize;
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;
use tracing::{info, instrument};

use crate::events::EventBus;
use crate::monitor::ProcessMonitor;
use crate::service::{
    InstanceConfig, InstanceRegistry, ServiceStatus, ServiceTemplate, TemplateRegistry,
};

/// Shared application state
#[derive(Clone)]
pub struct AppState {
    pub templates: Arc<RwLock<TemplateRegistry>>,
    pub instances: Arc<RwLock<InstanceRegistry>>,
    pub monitor: Arc<dyn ProcessMonitor>,
    pub event_bus: Arc<EventBus>,
}

/// Run the HTTP/WebSocket server
#[instrument(skip_all)]
pub async fn run_server(
    port: u16,
    templates: Arc<RwLock<TemplateRegistry>>,
    instances: Arc<RwLock<InstanceRegistry>>,
    monitor: Arc<dyn ProcessMonitor>,
    event_bus: Arc<EventBus>,
) -> Result<()> {
    let state = AppState {
        templates,
        instances,
        monitor,
        event_bus,
    };

    let app = Router::new()
        // Health check
        .route("/api/health", get(health_check))
        // Templates
        .route("/api/templates", get(list_templates))
        .route("/api/templates/:id", get(get_template))
        .route("/api/templates", post(create_template))
        // Instances
        .route("/api/instances", get(list_instances))
        .route("/api/instances/:id", get(get_instance))
        .route("/api/instances", post(create_instance))
        .route("/api/instances/:id/start", post(start_instance))
        .route("/api/instances/:id/stop", post(stop_instance))
        .route("/api/instances/:id/restart", post(restart_instance))
        // Metrics
        .route("/api/metrics", get(get_metrics))
        // WebSocket
        .route("/ws", get(websocket_handler))
        // CORS
        .layer(CorsLayer::permissive())
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
    info!(port = port, "USM Core server listening");

    axum::serve(listener, app).await?;
    Ok(())
}

// === Health Check ===

async fn health_check() -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "ok",
        "service": "USM Core",
        "version": env!("CARGO_PKG_VERSION")
    }))
}

// === Templates ===

async fn list_templates(State(state): State<AppState>) -> Json<Vec<ServiceTemplate>> {
    let templates = state.templates.read().await;
    Json(templates.list())
}

async fn get_template(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<ServiceTemplate>, StatusCode> {
    let templates = state.templates.read().await;
    templates.get(&id).map(Json).ok_or(StatusCode::NOT_FOUND)
}

async fn create_template(
    State(state): State<AppState>,
    Json(template): Json<ServiceTemplate>,
) -> Result<Json<ServiceTemplate>, (StatusCode, String)> {
    let mut templates = state.templates.write().await;
    templates
        .register(template.clone())
        .map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()))?;
    Ok(Json(template))
}

// === Instances ===

#[derive(Debug, Deserialize)]
struct InstanceQuery {
    template: Option<String>,
    tag: Option<String>,
    status: Option<String>,
}

/// Helper to insert CPU and memory metrics into a JSON object
fn insert_metrics(obj: &mut serde_json::Map<String, serde_json::Value>, cpu: f64, memory_bytes: u64) {
    obj.insert("cpu_percent".to_string(), serde_json::json!(cpu));
    obj.insert("memory_mb".to_string(), serde_json::json!(memory_bytes / (1024 * 1024)));
}

async fn list_instances(
    State(state): State<AppState>,
    Query(query): Query<InstanceQuery>,
) -> Json<serde_json::Value> {
    // Snapshot instance data while holding the lock, then release it
    let (list, counts, total) = {
        let instances = state.instances.read().await;
        let mut list = instances.list();

        // Filter by template
        if let Some(ref template) = query.template {
            list.retain(|i| &i.template_id == template);
        }

        // Filter by tag
        if let Some(ref tag) = query.tag {
            list.retain(|i| i.has_tag(tag));
        }

        // Filter by status
        if let Some(ref status) = query.status {
            let status = match status.as_str() {
                "running" => Some(ServiceStatus::Running),
                "stopped" => Some(ServiceStatus::Stopped),
                "error" => Some(ServiceStatus::Error),
                _ => None,
            };
            if let Some(s) = status {
                list.retain(|i| i.status == s);
            }
        }

        let counts = instances.status_counts();
        let total = instances.len();
        (list, counts, total)
    }; // Lock released here

    // Build instances with metrics (monitor calls are outside the lock)
    let instances_with_metrics: Vec<serde_json::Value> = list
        .iter()
        .map(|instance| {
            let mut json = match serde_json::to_value(instance) {
                Ok(v) => v,
                Err(e) => {
                    tracing::warn!("Failed to serialize instance {}: {}", instance.id, e);
                    serde_json::json!({})
                }
            };
            // Add metrics for running instances - try by port first (more reliable), then by PID
            if instance.status == ServiceStatus::Running {
                // Try to find process by port (most reliable for child processes)
                if let Some(info) = state.monitor.find_by_port(instance.port) {
                    if let Some(obj) = json.as_object_mut() {
                        insert_metrics(obj, info.cpu_percent, info.memory_bytes);
                    }
                } else if let Some(pid) = instance.pid {
                    // Fallback to stored PID
                    if let Some(metrics) = state.monitor.get_process_metrics(pid) {
                        if let Some(obj) = json.as_object_mut() {
                            insert_metrics(obj, metrics.cpu_percent, metrics.memory_bytes);
                        }
                    }
                }
            }
            json
        })
        .collect();

    Json(serde_json::json!({
        "instances": instances_with_metrics,
        "total": total,
        "running": counts.get(&ServiceStatus::Running).unwrap_or(&0),
        "stopped": counts.get(&ServiceStatus::Stopped).unwrap_or(&0),
        "error": counts.get(&ServiceStatus::Error).unwrap_or(&0)
    }))
}

async fn get_instance(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let instances = state.instances.read().await;
    let instance = instances.get(&id).ok_or(StatusCode::NOT_FOUND)?;

    // Get metrics if running
    let metrics = instance
        .pid
        .and_then(|pid| state.monitor.get_process_metrics(pid));

    Ok(Json(serde_json::json!({
        "instance": instance,
        "metrics": metrics
    })))
}

async fn create_instance(
    State(state): State<AppState>,
    Json(config): Json<InstanceConfig>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    // Verify template exists
    let templates = state.templates.read().await;
    let template = templates.get(&config.template_id).ok_or((
        StatusCode::BAD_REQUEST,
        format!("Template '{}' not found", config.template_id),
    ))?;

    // Determine port
    let port = config.port.unwrap_or(template.default_port);
    drop(templates);

    // Create instance
    let mut config = config;
    config.port = Some(port);

    let instance = crate::service::ServiceInstance::from_config(config.clone())
        .map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()))?;

    let instance_id = instance.id.clone();

    let mut instances = state.instances.write().await;
    instances
        .add(instance)
        .map_err(|e| (StatusCode::CONFLICT, e.to_string()))?;

    Ok(Json(serde_json::json!({
        "status": "ok",
        "instance_id": instance_id,
        "port": port
    })))
}

async fn start_instance(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let mut instances = state.instances.write().await;
    let instance = instances.get_mut(&id).ok_or((
        StatusCode::NOT_FOUND,
        format!("Instance '{}' not found", id),
    ))?;

    // Check if already running
    if instance.status == ServiceStatus::Running {
        return Ok(Json(serde_json::json!({
            "status": "ok",
            "message": format!("Instance {} is already running", id),
            "pid": instance.pid
        })));
    }

    // Get template for start command
    let templates = state.templates.read().await;
    let template = templates.get(&instance.template_id).ok_or((
        StatusCode::BAD_REQUEST,
        format!("Template '{}' not found", instance.template_id),
    ))?;

    // Build and execute start command
    let command = template.build_start_command(instance);
    let pid = state
        .monitor
        .start_process(&command, instance.working_dir.as_deref())
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    // Update instance state
    instance.status = ServiceStatus::Running;
    instance.pid = Some(pid);
    instance.started_at = Some(chrono::Utc::now());

    // Broadcast event
    state
        .event_bus
        .send(crate::events::ServiceEvent::StatusChanged {
            instance_id: id.clone(),
            status: ServiceStatus::Running,
            pid: Some(pid),
        });

    info!(instance_id = %id, pid = %pid, "Instance started via HTTP API");

    Ok(Json(serde_json::json!({
        "status": "ok",
        "message": format!("Started instance {}", id),
        "pid": pid
    })))
}

async fn stop_instance(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    let mut instances = state.instances.write().await;
    let instance = instances.get_mut(&id).ok_or((
        StatusCode::NOT_FOUND,
        format!("Instance '{}' not found", id),
    ))?;

    // Check if already stopped
    if instance.status != ServiceStatus::Running {
        return Ok(Json(serde_json::json!({
            "status": "ok",
            "message": format!("Instance {} is already stopped", id)
        })));
    }

    // Get template for optional custom stop command
    let templates = state.templates.read().await;
    let template = templates.get(&instance.template_id);

    // Stop the process
    if let Some(pid) = instance.pid {
        if let Some(tmpl) = template {
            if let Some(stop_cmd) = &tmpl.stop_command {
                let cmd = stop_cmd.replace("{pid}", &pid.to_string());
                state
                    .monitor
                    .execute_command(&cmd)
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
            } else {
                state
                    .monitor
                    .kill_process(pid)
                    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
            }
        } else {
            state
                .monitor
                .kill_process(pid)
                .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        }
    }

    // Update instance state
    instance.status = ServiceStatus::Stopped;
    instance.pid = None;
    instance.started_at = None;

    // Broadcast event
    state
        .event_bus
        .send(crate::events::ServiceEvent::StatusChanged {
            instance_id: id.clone(),
            status: ServiceStatus::Stopped,
            pid: None,
        });

    info!(instance_id = %id, "Instance stopped via HTTP API");

    Ok(Json(serde_json::json!({
        "status": "ok",
        "message": format!("Stopped instance {}", id)
    })))
}

async fn restart_instance(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    // Stop first
    let mut instances = state.instances.write().await;
    let instance = instances.get_mut(&id).ok_or((
        StatusCode::NOT_FOUND,
        format!("Instance '{}' not found", id),
    ))?;

    // Get template
    let templates = state.templates.read().await;
    let template = templates.get(&instance.template_id).ok_or((
        StatusCode::BAD_REQUEST,
        format!("Template '{}' not found", instance.template_id),
    ))?;

    // Stop if running
    if instance.status == ServiceStatus::Running {
        if let Some(pid) = instance.pid {
            if let Some(stop_cmd) = &template.stop_command {
                let cmd = stop_cmd.replace("{pid}", &pid.to_string());
                let _ = state.monitor.execute_command(&cmd);
            } else {
                let _ = state.monitor.kill_process(pid);
            }
        }
        instance.status = ServiceStatus::Stopped;
        instance.pid = None;
    }

    // Brief delay before restart
    drop(templates);
    drop(instances);
    tokio::time::sleep(tokio::time::Duration::from_secs(1)).await;

    // Start again
    let mut instances = state.instances.write().await;
    let instance = instances.get_mut(&id).ok_or((
        StatusCode::NOT_FOUND,
        format!("Instance '{}' not found after stop", id),
    ))?;

    let templates = state.templates.read().await;
    let template = templates.get(&instance.template_id).ok_or((
        StatusCode::BAD_REQUEST,
        format!("Template '{}' not found", instance.template_id),
    ))?;

    let command = template.build_start_command(instance);
    let pid = state
        .monitor
        .start_process(&command, instance.working_dir.as_deref())
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    instance.status = ServiceStatus::Running;
    instance.pid = Some(pid);
    instance.started_at = Some(chrono::Utc::now());

    state
        .event_bus
        .send(crate::events::ServiceEvent::StatusChanged {
            instance_id: id.clone(),
            status: ServiceStatus::Running,
            pid: Some(pid),
        });

    info!(instance_id = %id, pid = %pid, "Instance restarted via HTTP API");

    Ok(Json(serde_json::json!({
        "status": "ok",
        "message": format!("Restarted instance {}", id),
        "pid": pid
    })))
}

// === Metrics ===

async fn get_metrics(State(state): State<AppState>) -> Json<serde_json::Value> {
    let system = state.monitor.get_system_metrics();
    let instances = state.instances.read().await;
    let counts = instances.status_counts();

    Json(serde_json::json!({
        "system": {
            "cpu_percent": system.cpu_percent,
            "memory_used_gb": system.memory_used_gb(),
            "memory_total_gb": system.memory_total_gb(),
            "memory_percent": system.memory_percent
        },
        "instances": {
            "running": counts.get(&ServiceStatus::Running).unwrap_or(&0),
            "stopped": counts.get(&ServiceStatus::Stopped).unwrap_or(&0),
            "error": counts.get(&ServiceStatus::Error).unwrap_or(&0),
            "total": instances.len()
        }
    }))
}

// === WebSocket ===

async fn websocket_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_websocket(socket, state))
}

async fn handle_websocket(mut socket: axum::extract::ws::WebSocket, state: AppState) {
    use axum::extract::ws::Message;

    // Send initial state
    let instances = state.instances.read().await;
    let initial = serde_json::json!({
        "type": "connected",
        "instances": instances.list()
    });
    drop(instances);

    if socket
        .send(Message::Text(initial.to_string()))
        .await
        .is_err()
    {
        return;
    }

    // Subscribe to events
    let mut rx = state.event_bus.subscribe();

    loop {
        tokio::select! {
            // Forward events to WebSocket
            Ok(event) = rx.recv() => {
                let json = serde_json::to_string(&event).unwrap_or_default();
                if socket.send(Message::Text(json)).await.is_err() {
                    break;
                }
            }
            // Handle incoming messages (ping/pong)
            Some(msg) = socket.recv() => {
                match msg {
                    Ok(Message::Ping(data)) => {
                        if socket.send(Message::Pong(data)).await.is_err() {
                            break;
                        }
                    }
                    Ok(Message::Close(_)) | Err(_) => break,
                    _ => {}
                }
            }
        }
    }
}
