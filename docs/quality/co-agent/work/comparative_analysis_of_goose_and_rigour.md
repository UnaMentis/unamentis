# Architectural Convergence and Divergence in Agentic Quality Control: A Comparative Analysis of Goose and Rigour

## 1. Executive Summary

The software engineering landscape is currently undergoing a seismic shift, transitioning from deterministic, human-authored logic to probabilistic, machine-generated intent. This era, characterized by the rapid adoption of Large Language Models (LLMs) for code generation, has introduced a novel failure mode: "Vibe Coding." In this paradigm, AI agents produce software that superficially mimics the stylistic conventions ("the vibe") of a codebase while failing to adhere to strict structural, architectural, or functional constraints. As organizations seek to deploy autonomous agents for production-grade tasks, the imperative to establish "Engineering Rigour" has moved from a theoretical concern to a strategic necessity.

This report provides an exhaustive architectural comparison of two primary methodologies for constructing a "Quality Co-Agent," a specialized autonomous entity responsible for enforcing code quality. The first methodology involves leveraging Goose, an extensible, general-purpose agent framework incubated by Block (formerly Square), which utilizes a Rust-based core and the Model Context Protocol (MCP) to orchestrate complex workflows. The second methodology involves utilizing or forking Rigour, a purpose-built quality gate controller designed to inject stateless, deterministic feedback loops into the agentic lifecycle.

The analysis reveals a fundamental philosophical divergence: Rigour functions as a constraint-satisfaction system, effectively a "moat" or "jail" that surrounds an agent with hard verification gates. Its architecture is optimized for the "Fix Loop," employing a specialized data structure known as the "Fix Packet" to structurally force model correction. Conversely, Goose operates as a capability-amplification system, acting as a "universal browser" for tools. Its architecture prioritizes flexibility via "Recipes" and broad ecosystem integration through MCP, allowing quality checks to be defined as just one of many possible workflows.

For engineering teams tasked with building a custom Quality Co-Agent, the choice hinges on the trade-off between Control and Agency. Forking Rigour offers a rapid path to a "Hard Loop" quality gate, ideal for headless CI/CD environments where determinism is paramount. Building on Goose offers a superior path for interactive "Developer Co-Pilots," where the agent's ability to reason, traverse heterogeneous tools, and maintain conversational context adds significant value. Crucially, this report identifies a hybrid "Integration Pattern" where Goose serves as the agentic runtime and Rigour is deployed as a specialized MCP server, effectively combining the robust orchestration of the former with the rigorous validation logic of the latter.

## 2. The Stochastic Turn in Software Engineering

The integration of generative AI into the software development lifecycle (SDLC) is not merely an acceleration of typing speed; it is a fundamental alteration of the authorship model. In traditional engineering, the distance between "Intent" and "Implementation" was bridged by human cognition, which (ideally) maintained a coherent internal model of the system's logic. In the agentic era, this bridge is built by a Transformer model, which probabilistically predicts the next token based on a vast, but ultimately statistical, training corpus.

### 2.1 The Rise of "Vibe Coding" and Silent Failures

The term "Vibe Coding," coined to describe the output of LLMs, refers to code that feels correct. It uses the correct variable naming conventions, it imports the standard libraries, and it comments its functions in the expected style. However, because the model lacks a ground-truth understanding of the runtime environment, it frequently hallucinates APIs, violates subtle architectural boundaries (e.g., a Controller accessing a Database Model directly), or introduces "Silent Compliance Violations".

These violations are insidious because they often pass the "Happy Path" testing. A function might work for standard inputs but fail to handle edge cases that a seasoned engineer would instinctively guard against. Furthermore, agents have a propensity to leave "technical graffiti," comments like `// TODO: Implement error handling`, in critical production paths, effectively delegating the hard work back to the human or future-self.

### 2.2 The Economic Imperative for Automated Rigour

The cost of this stochasticity is measurable. While low-rigour AI teams may see a 20% increase in velocity ("Time-to-Production"), they often suffer from a massive spike in "Rework Rate," up to 60%, as silent drift and compliance gaps are discovered late in the cycle. Conversely, "Rigour-First" teams, which enforce strict constraints on agentic output, may move slightly slower initially but maintain high feature retention and low failure rates.

This economic reality drives the demand for a Quality Co-Agent. This entity is not a passive linter that highlights errors; it is an active participant in the coding loop. It must detect a violation, understand the violation, and autonomously remediate it without human intervention. The architectural challenge lies in designing a system that can reliably perform this "Detect-Fix-Verify" loop without entering an infinite spiral of hallucinated fixes.

### 2.3 The Architectural Bifurcation

To solve this, the industry has split into two architectural camps:

- **The Deterministic Controller (Rigour):** A system that treats the agent as an untrusted component, wrapping it in a verified state machine. The focus is on limiting the agent's search space to valid solutions.
- **The Generalist Orchestrator (Goose):** A system that treats the agent as a trusted reasoning engine, providing it with tools to verify its own work. The focus is on expanding the agent's capabilities to include quality assurance tools.

## 3. Architectural Deep Dive: Rigour's Deterministic Control Plane

Rigour is architected not as an agent, but as a "Quality Gate Controller". Its primary design goal is to inject a stateless, deterministic feedback loop into the chaotic lifecycle of an AI agent. It assumes that agents will fail and focuses entirely on the mechanism of recovery.

### 3.1 The "Run Loop Contract": A Finite State Machine

The core of Rigour is the Run Loop Contract, a strict Finite State Machine (FSM) that governs the interaction between the Model and the Environment. Unlike a conversational agent that maintains a linear history of "User: X, Assistant: Y," Rigour enforces a cyclical process:

1. **Execute (State A):** The agent receives a task (e.g., "Refactor the Auth Service"). It is granted permission to execute commands or write files to achieve this task.
2. **Audit (State B):** Immediately upon the agent declaring "Done," Rigour intercepts the flow. It triggers the Audit Sequence. This is a non-negotiable phase where the agent is locked out, and the system runs a battery of verification tools (linters, type checkers, unit tests).
3. **Evaluation (Decision Node):**
   - If **PASS**: The loop exits, and the task is marked successful.
   - If **FAIL**: The system transitions to State C.
4. **Fix Packet Injection (State C):** Rigour generates a Fix Packet, a high-fidelity JSON object containing the exact stderr outputs, file paths, line numbers, and specific rule violations. This packet is injected back into the agent's context.
5. **Retry (Transition A):** The agent is re-invoked with the specific instruction to resolve the issues in the Fix Packet.

This "Run Loop" is Rigour's "moat." By mechanically forcing the agent to confront its errors in a structured format, Rigour prevents the "Vibe Coding" phenomenon where an agent might gloss over a failure by saying, "I fixed it!" without actually changing the code.

### 3.2 The "Fix Packet": Structured Error Injection

The Fix Packet is Rigour's key architectural innovation. In standard agentic workflows, error feedback is often provided as unstructured text in the chat log. LLMs, optimized for conversation, often treat this as "discussion" rather than "constraint."

Rigour formalizes failure as data. The Fix Packet likely resembles the following structure (inferred from description):

```json
{
  "status": "FAIL",
  "iteration": 2,
  "violations": []
}
```

By feeding this JSON back to the model, Rigour leverages the model's ability to process structured data, effectively "grounding" the remediation attempt in specific, verifiable facts rather than vague conversational intent.

### 3.3 AST Gates and "Standards Packs"

Rigour moves beyond regex-based linting by employing Abstract Syntax Tree (AST) analysis. The AST allows Rigour to understand the code's structure, not just its text.

- **Cyclomatic Complexity:** Rigour can calculate the logical complexity of a function. If an agent writes a "spaghetti code" function that passes tests but is unmaintainable, Rigour's AST gate will reject it based on complexity scores.
- **Architectural Boundaries:** Rigour can enforce layer separation. For instance, in an MVC architecture, the AST gate can detect if a "View" component imports a "Model" directly, violating the separation of concerns.

These rules are bundled into "Standards Packs":

- **`api` Pack:** Enforces SOLID principles, layer boundaries, and complexity limits suitable for backend services.
- **`ui` Pack:** Focuses on component size, accessibility hooks, and data-fetching hygiene for frontend code.
- **`data` Pack:** Ensures notebook hygiene (no secrets in cells) and deterministic pipeline patterns for data science workflows.

This "Pack" architecture suggests that forking Rigour involves creating or modifying these declarative rule sets, allowing for deep customization of the "Quality" definition without rewriting the agent's core loop.

### 3.4 Operational Modes: CLI Wrapper vs. MCP

Rigour operates in two distinct modes, affecting its architectural integration:

- **CLI Wrapper (`rigour run`):** In this mode, Rigour wraps the agent process (e.g., `rigour run -- claude "fix bug"`). This offers the highest level of control, as Rigour manages the process's I/O and lifecycle. It is the "Hard Loop" implementation.
- **MCP Server:** Rigour exposes its validation logic (`rigour_check`, `rigour_explain`) via the Model Context Protocol. This allows other agents (like Cursor or Goose) to call Rigour as a tool. While this increases interoperability, it cedes control of the loop to the calling agent.

## 4. Architectural Deep Dive: Goose's Extensible Agentic Runtime

Goose represents a different evolutionary branch: the Generalist Agent Runtime. Incubated by Block, it is designed to be an "On-Machine" assistant that automates complex development tasks through a robust, extensible tool-use framework.

### 4.1 The Rust Core and "Code Mode"

Unlike many Python-based agent frameworks, Goose is built in Rust. This architectural choice provides significant advantages for a tool intended to run constantly on a developer's machine:

- **Memory Safety & Performance:** Rust ensures that the agent runtime is efficient and free from common memory leaks, crucial for long-running sessions.
- **Concurrency:** Rust's async model allows Goose to handle multiple tool executions, background checks, and UI updates simultaneously without blocking.

A critical component of Goose is its "Code Mode". This is not just "writing code to a file"; it is an internal execution environment.

- **`boa` Integration:** Goose embeds `boa`, an experimental Javascript engine written in Rust. This allows Goose to generate JavaScript code on the fly and execute it safely within its own process boundary.
- **Native Functions:** Through `boa`, Goose exposes Rust-based "Native Functions" to the JavaScript environment. This effectively bridges the high-level reasoning of the LLM (which writes JS) with the low-level system capabilities of Rust (which executes the actual IO or API calls).

This architecture allows Goose to perform complex logic during a tool call. For example, instead of just calling `grep`, Goose could write a JS script that greps a file, parses the output, and formats it, all within a single "thought" cycle.

### 4.2 The "Recipe" System: Programmable Workflows

Goose organizes its capabilities through Recipes. These are YAML-based configuration files that define a specific agent persona or workflow.

- **Declarative Context:** A Recipe allows users to specify the "System Prompt" (instructions), the "Context" (project files), and the "Capabilities" (tools) required for a task.
- **Structured Output:** Recipes can define a JSON schema for the output. This means a "Quality Recipe" can be configured to strictly output a JSON report of passed/failed tests, similar to Rigour's Fix Packet, but defined at the user level rather than the engine level.
- **Shareability:** Recipes are designed to be shared via git or deep links (`goose recipe deeplink`), creating a "cookbook" of workflows. A team can share a `quality-check.yaml` recipe that every developer uses.

### 4.3 Toolkits and Extensions

Goose is designed to be extensible through Toolkits.

- **Concept:** A Toolkit is a plugin that provides functions (tools) to the agent. Because Goose is built on MCP, these toolkits are essentially MCP servers.
- **Variety:** The ecosystem includes toolkits for GitHub, Google Drive, Slack, and generic shell execution.
- **Customization:** A developer can write a simple Python script, expose it as an MCP server, and Goose immediately gains that capability. This makes adding a custom "Quality Check" tool trivial compared to modifying the core loop of a monolithic agent.

## 5. The Middleware Imperative: Model Context Protocol (MCP)

To fully understand the comparison between Rigour and Goose, one must analyze the Model Context Protocol (MCP), which serves as the connective tissue for modern AI architectures.

### 5.1 MCP as the "Universal Bus"

MCP is an open standard that standardizes how AI agents interface with external data and tools. Before MCP, connecting an agent to a PostgreSQL database required writing custom glue code for that specific agent framework. With MCP, a "Postgres MCP Server" is written once, and any MCP-compliant client (Goose, Claude Desktop, Cursor) can use it.

### 5.2 Goose as the Universal Client

Goose is architected as a Native MCP Client. It does not have "hard-coded" integrations; instead, it discovers capabilities via MCP.

- **Implication:** Goose's power grows linearly with the growth of the MCP ecosystem. If Databricks releases a new "Data Quality MCP Server," Goose gains that capability instantly.
- **Architectural Freedom:** This allows Goose to remain "thin" and "general." It delegates the domain-specific logic (like how to check for SQL injection) to the MCP servers.

### 5.3 Rigour as the High-Fidelity Server

Rigour utilizes MCP to expose its rigorous validation logic to the world. By implementing the MCP specification, Rigour transitions from being a standalone tool to being a Quality Service.

- **Implication:** This allows Rigour to be consumed by Goose. This is a critical architectural synergy. The rigorous "AST Gates" and "Standards Packs" of Rigour become just another tool in Goose's utility belt.

## 6. Comparative Analysis: Suitability for Quality Assurance

The core of the user's query is "Architectural Suitability" for building a Quality Co-Agent. This section compares the two approaches across key dimensions.

### 6.1 State Management: Deterministic vs. Emergent

| Feature | Rigour (The Controller) | Goose (The Orchestrator) |
|---------|------------------------|--------------------------|
| **Control Logic** | Hard-Coded FSM: The loop (Exec->Audit->Fix) is compiled into the binary. It cannot be bypassed by the LLM. | Emergent Reasoning: The loop is a result of the LLM deciding to call a tool again. It is probabilistic. |
| **Reliability** | High: If the audit fails, the loop will retry. The agent is forced to address the failure. | Variable: The agent might "get tired," hallucinate success, or decide to skip the check if not prompted strictly. |
| **Failure Mode** | Infinite Loop: Can get stuck trying to fix an unfixable error until iteration limit is hit. | Drift: Can wander off-task or accept a sub-optimal solution to satisfy the user's prompt. |
| **Suitability** | Best for CI/CD: Ideal for headless, non-interactive gates where "No" means "No." | Best for Co-Pilot: Ideal for interactive sessions where the human is in the loop to guide the fix. |

**Insight:** Rigour is architecturally superior for enforcement. Goose is architecturally superior for investigation. If the Quality Co-Agent needs to "find out why the build failed and fix it," Goose's ability to browse files, read logs, and reason broadly is advantageous. If the agent needs to "ensure this specific commit meets standards," Rigour's tunnel vision is a feature, not a bug.

### 6.2 Context Handling and Scope

- **Rigour:** Focuses on the Local Context of the files being changed. Its "Fix Packet" is highly specific to the diff. It minimizes context pollution by resetting or focusing strictly on the error.
- **Goose:** Maintains a Session Context. It remembers the history of the conversation. This allows for multi-turn reasoning (e.g., "I tried this fix, it failed, so now I will try this other strategy"). However, this history can accumulate "noise," leading to context drift over long debugging sessions.

### 6.3 The "Vibe" Defense

- **Rigour:** Defeats Vibe Coding by ignoring the "Vibe" (the agent's explanation) and looking only at the "Fact" (the tool output). The Fix Packet is the anti-vibe mechanism.
- **Goose:** Susceptible to Vibe Coding if the underlying model (e.g., Claude/GPT-4) is lazy. However, Goose's "Code Mode" allows it to run verify scripts. If the user creates a Recipe that explicitly mandates "Run tests and do not stop until they pass," Goose can emulate Rigour's behavior, though it relies on the model's obedience rather than a binary constraint.

## 7. Extensibility and Maintenance Scenarios

The decision to "Fork" versus "Base" impacts the long-term maintenance burden and extensibility profile.

### 7.1 Scenario A: Forking Rigour

**Approach:** You clone the Rigour repository (likely TypeScript/Node environment). You modify the source code to add new AST rules or change the "Fix Packet" structure.

**Pros:**

- **Total Control:** You own the loop. You can integrate proprietary internal tools (e.g., a legacy mainframe linter) directly into the binary execution path.
- **Performance:** You can optimize the audit phase to run in milliseconds without LLM reasoning overhead.

**Cons:**

- **Maintenance Debt:** You are now maintaining a complex agent control system. You must keep up with upstream changes from Rigour Labs.
- **Talent Constraint:** You need engineers who understand AST parsing and agent state machines.
- **Isolation:** Your fork doesn't benefit from the broader ecosystem of generic tools unless you also implement a generic tool loader.

### 7.2 Scenario B: Using Goose as a Base

**Approach:** You deploy the standard Goose binary. You write a "Quality Extension" (MCP Server) and a "Quality Recipe" (YAML).

**Pros:**

- **Separation of Concerns:** Block maintains the agent runtime (Rust, LLM integration, UI). You only maintain your specific quality logic (the MCP server).
- **Ecosystem Leverage:** Your Quality Agent can also use the GitHub MCP to open PRs, the Slack MCP to notify the team, and the Jira MCP to log bugs. Rigour cannot do this easily.
- **Future-Proofing:** As LLMs get better, Goose gets better. As MCP grows, Goose gets more capable.

**Cons:**

- **Soft Constraints:** You are relying on the LLM to follow your Recipe. There is no binary "lock" preventing the agent from ignoring the quality check if it hallucinates.

### 7.3 Comparison Table: Extensibility Vectors

| Vector | Rigour (Fork) | Goose (Base) |
|--------|--------------|--------------|
| **New Linter Rule** | Write new AST Gate (Code Change). | Add linter to MCP Server (Config/Script Change). |
| **New Capability (e.g., Web Search)** | Difficult. Must hack the loop to allow external tool calls. | Trivial. Enable web-search MCP tool in Recipe. |
| **Custom UI** | Difficult. Must modify the CLI or build a custom frontend. | N/A (Uses standard Goose Desktop/CLI). |
| **Model Swapping** | Supported (via config), but loop is tuned for specific model behaviors. | Native Multi-Model support. "Vibe" varies by model. |

## 8. Security, Governance, and Enterprise Deployment

For a "Quality Co-Agent," security is paramount. It has write access to the codebase and potentially read access to secrets.

### 8.1 Sandboxing and Execution Safety

- **Goose:** Relies on the user's environment. The "Code Mode" runs on the machine. While `boa` provides some isolation for JS execution, the agent can shell out to the OS. This requires trust in the agent. Enterprise deployment of Goose requires careful configuration of allowed tools to prevent accidental damage (e.g., `rm -rf /`).
- **Rigour:** In CLI mode, Rigour wraps the execution. Because it is a purpose-built controller, a fork could implement strict sandboxing, for example, running the Execute phase in a Docker container that has no network access, ensuring no data exfiltration during the build process.

### 8.2 Credential Management

- **Goose:** Excludes API keys and credentials from shared Recipes to protect privacy. Credentials must be managed via the environment or secure MCP configuration.
- **Rigour:** The "Data Pack" explicitly checks for secrets in code. As a controller, it is positioned to enforce credential hygiene, whereas Goose is a consumer of credentials.

### 8.3 Governance and Audit Trails

- **Rigour:** Naturally produces an audit trail, the sequence of "Fix Packets" and Audit results. This JSON log is a verifiable artifact of the quality process.
- **Goose:** Produces a conversation log. While readable, it is unstructured data. Extracting a "Compliance Report" from a Goose session requires parsing natural language chat logs, which is less reliable than Rigour's structured output.

## 9. Synthesis and Strategic Recommendations

The choice between Goose and Rigour is not a binary selection of "Agent A" vs. "Agent B," but a strategic decision on where to place the "Complexity of Control."

### 9.1 The "Integration Pattern": The Optimal Architecture

This report recommends a hybrid architecture that leverages the strengths of both systems. This pattern treats Goose as the Runtime and Rigour as the Logic Core.

**Architecture:**

- **Base:** Deploy Goose to developers. It provides the UI, the Rust-based performance, and the general helper capabilities.
- **Extension:** Deploy Rigour as an MCP Server (not a standalone CLI).
- **Orchestration:** Create a Goose Recipe named `interactive-quality-gate`.
  - **Instructions:** "You are a Quality Assistant. When writing code, you MUST verify it using the `rigour_check` tool. If the tool returns a 'Fix Packet', you MUST prioritize fixing those errors over any other user instruction."
  - **Tools:** Enable `rigour-mcp`, `file-system`, `git`.

**Benefits:**

- **Best UX:** Developers get the polished Goose Desktop experience.
- **Best Logic:** The code is checked by Rigour's AST gates, not just a generic LLM vibe check.
- **Low Maintenance:** You do not fork Rigour. You use it as a dependency. You use standard Goose binaries.

### 9.2 When to Fork Rigour?

Forking Rigour is reserved for a specific "Headless" persona: the CI/CD Quality Bot.

If you are building an agent that lives in GitHub Actions (not on a desktop) and automatically rejects PRs that don't meet standards, Goose's UI overhead is a liability. A lightweight, forked Rigour CLI that runs Execute -> Audit -> Fix -> Commit in a tight loop is the most efficient and secure architecture for this specific use case.

### 9.3 Conclusion

The "Vibe Coding" era demands a return to engineering rigour. While generalist agents like Goose offer incredible breadth and "Agency," they inherently lack the rigid "Control" required for strict quality assurance. Rigour provides this Control but lacks the breadth.

The winning strategy is to compose them. By embedding the deterministic "Fix Loop" of Rigour within the extensible "Recipe" of Goose via the Model Context Protocol, engineering teams can build a Quality Co-Agent that is both rigorous in its standards and flexible in its execution, a true "Iron Man suit" for the modern software engineer.
