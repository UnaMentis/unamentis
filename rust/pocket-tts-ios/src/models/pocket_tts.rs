//! Complete Pocket TTS Model
//!
//! Combines FlowLM transformer, MLP sampler, and Mimi decoder
//! into a complete text-to-speech pipeline.

use std::path::Path;

use candle_core::{DType, Device, Tensor};
use candle_nn::VarBuilder;

use super::flowlm::{FlowLM, FlowLMConfig};
use super::mimi::{MimiConfig, MimiDecoder};
use crate::config::TTSConfig;
use crate::modules::embeddings::{VoiceBank, VoiceEmbedding};
use crate::modules::mlp::MLPSampler;
use crate::tokenizer::PocketTokenizer;
use crate::error::PocketTTSError;

/// Complete Pocket TTS Model
pub struct PocketTTSModel {
    flowlm: FlowLM,
    sampler: MLPSampler,
    mimi: MimiDecoder,
    tokenizer: PocketTokenizer,
    voice_bank: VoiceBank,
    device: Device,
    config: TTSConfig,
    custom_voice: Option<VoiceEmbedding>,
}

impl PocketTTSModel {
    /// Load model from directory containing all components
    pub fn load<P: AsRef<Path>>(model_dir: P, device: &Device) -> std::result::Result<Self, PocketTTSError> {
        let model_dir = model_dir.as_ref();

        // Load model weights using memory-mapped file
        let model_path = model_dir.join("model.safetensors");

        // Create VarBuilder from safetensors file
        let vb = unsafe {
            VarBuilder::from_mmaped_safetensors(&[&model_path], DType::F32, device)
                .map_err(|e| PocketTTSError::ModelLoadFailed(e.to_string()))?
        };

        // Load tokenizer (JSON vocab format)
        let tokenizer_path = model_dir.join("tokenizer.json");
        let tokenizer = PocketTokenizer::from_file(&tokenizer_path)?;

        // Load voice embeddings
        let voices_dir = model_dir.join("voices");
        let voice_bank = VoiceBank::load_from_dir(&voices_dir, device)
            .map_err(|e| PocketTTSError::ModelLoadFailed(format!("Failed to load voices: {}", e)))?;

        // Initialize model components
        let flowlm_config = FlowLMConfig::default();
        let flowlm = FlowLM::new(flowlm_config.clone(), vb.pp("flowlm"), device)
            .map_err(|e| PocketTTSError::ModelLoadFailed(format!("FlowLM: {}", e)))?;

        let sampler = MLPSampler::new(
            flowlm_config.latent_dim,
            512,
            flowlm_config.latent_dim,
            4,
            vb.pp("sampler"),
        ).map_err(|e| PocketTTSError::ModelLoadFailed(format!("Sampler: {}", e)))?;

        let mimi_config = MimiConfig {
            latent_dim: flowlm_config.latent_dim,
            ..MimiConfig::default()
        };
        let mimi = MimiDecoder::new(mimi_config, vb.pp("mimi"))
            .map_err(|e| PocketTTSError::ModelLoadFailed(format!("Mimi: {}", e)))?;

        Ok(Self {
            flowlm,
            sampler,
            mimi,
            tokenizer,
            voice_bank,
            device: device.clone(),
            config: TTSConfig::default(),
            custom_voice: None,
        })
    }

    /// Configure synthesis parameters
    pub fn configure(&mut self, config: TTSConfig) -> std::result::Result<(), PocketTTSError> {
        config.validate().map_err(PocketTTSError::InvalidConfig)?;
        self.config = config;
        Ok(())
    }

    /// Set custom voice from reference audio embedding
    pub fn set_custom_voice(&mut self, embedding: VoiceEmbedding) {
        self.custom_voice = Some(embedding);
    }

    /// Clear custom voice (use built-in)
    pub fn clear_custom_voice(&mut self) {
        self.custom_voice = None;
    }

    /// Synthesize text to audio
    pub fn synthesize(&mut self, text: &str) -> std::result::Result<Vec<f32>, PocketTTSError> {
        // Tokenize text
        let token_ids = self.tokenizer.encode(text)?;

        // Create tensor
        let token_tensor = Tensor::from_vec(
            token_ids.iter().map(|&id| id as i64).collect::<Vec<_>>(),
            (1, token_ids.len()),
            &self.device,
        ).map_err(|e| PocketTTSError::InferenceFailed(e.to_string()))?;

        // Get voice embedding
        let voice = if let Some(ref custom) = self.custom_voice {
            Some(custom)
        } else {
            self.voice_bank.get(self.config.voice_index as usize)
        };

        // Reset caches for new sequence
        self.flowlm.reset_cache();

        // Generate latents with FlowLM
        let latents = self.flowlm.forward(&token_tensor, voice, false)
            .map_err(|e| PocketTTSError::InferenceFailed(format!("FlowLM: {}", e)))?;

        // Apply consistency sampling
        let sampled = self.sampler.sample(
            &latents,
            self.config.temperature,
            self.config.top_p,
        ).map_err(|e| PocketTTSError::InferenceFailed(format!("Sampler: {}", e)))?;

        // Decode to audio
        let audio = self.mimi.forward(&sampled)
            .map_err(|e| PocketTTSError::InferenceFailed(format!("Mimi: {}", e)))?;

        // Convert to Vec<f32>
        let audio = audio.squeeze(0)
            .map_err(|e| PocketTTSError::InferenceFailed(e.to_string()))?;
        let audio_vec: Vec<f32> = audio.to_vec1()
            .map_err(|e| PocketTTSError::InferenceFailed(e.to_string()))?;

        Ok(audio_vec)
    }

    /// Streaming synthesis - yields audio chunks
    pub fn synthesize_streaming<F>(
        &mut self,
        text: &str,
        chunk_callback: F,
    ) -> std::result::Result<(), PocketTTSError>
    where
        F: Fn(&[f32], bool) -> bool, // Returns false to stop
    {
        // Tokenize text
        let token_ids = self.tokenizer.encode(text)?;

        // Get voice embedding
        let voice = if let Some(ref custom) = self.custom_voice {
            Some(custom)
        } else {
            self.voice_bank.get(self.config.voice_index as usize)
        };

        // Reset caches
        self.flowlm.reset_cache();

        // Process in chunks for streaming
        let chunk_size = 32; // tokens per chunk
        let overlap_samples = (self.mimi.sample_rate() as f32 * 0.05) as usize; // 50ms overlap
        let mut previous_tail: Option<Tensor> = None;

        for (i, chunk) in token_ids.chunks(chunk_size).enumerate() {
            let is_last = i == (token_ids.len() / chunk_size);

            // Create tensor for chunk
            let token_tensor = Tensor::from_vec(
                chunk.iter().map(|&id| id as i64).collect::<Vec<_>>(),
                (1, chunk.len()),
                &self.device,
            ).map_err(|e| PocketTTSError::InferenceFailed(e.to_string()))?;

            // Generate latents (use cache for efficiency)
            let latents = self.flowlm.forward(&token_tensor, voice, true)
                .map_err(|e| PocketTTSError::InferenceFailed(format!("FlowLM: {}", e)))?;

            // Sample
            let sampled = self.sampler.sample(
                &latents,
                self.config.temperature,
                self.config.top_p,
            ).map_err(|e| PocketTTSError::InferenceFailed(format!("Sampler: {}", e)))?;

            // Decode with overlap-add
            let (audio, tail) = self.mimi.decode_streaming(
                &sampled,
                overlap_samples,
                previous_tail.as_ref(),
            ).map_err(|e| PocketTTSError::InferenceFailed(format!("Mimi: {}", e)))?;

            previous_tail = Some(tail);

            // Convert to Vec<f32>
            let audio = audio.squeeze(0)
                .map_err(|e| PocketTTSError::InferenceFailed(e.to_string()))?;
            let audio_vec: Vec<f32> = audio.to_vec1()
                .map_err(|e| PocketTTSError::InferenceFailed(e.to_string()))?;

            // Callback with audio chunk
            if !chunk_callback(&audio_vec, is_last) {
                break; // User requested stop
            }
        }

        Ok(())
    }

    /// Get sample rate
    pub fn sample_rate(&self) -> u32 {
        self.mimi.sample_rate() as u32
    }

    /// Get parameter count
    pub fn parameter_count(&self) -> u64 {
        117_856_642 // From model manifest
    }

    /// Get model version
    pub fn version(&self) -> &str {
        "1.0.2"
    }
}

impl std::fmt::Debug for PocketTTSModel {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PocketTTSModel")
            .field("version", &self.version())
            .field("parameter_count", &self.parameter_count())
            .field("sample_rate", &self.sample_rate())
            .field("voice_count", &self.voice_bank.len())
            .finish()
    }
}
