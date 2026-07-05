const metadata = {
  "id": "fyxer",
  "displayName": "Fyxer",
  "description": "Fyxer for OpenClaw lets you write emails that sound like you, right from the chat.",
  "version": "1.0.2",
  "toolName": "fyxer",
  "workflowCount": 0
};

const ToolSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    action: {
      type: "string",
      enum: ["status", "help"],
      description: "Action to run.",
      default: "status"
    }
  }
};

function textResult(text, details = {}) {
  return {
    content: [{ type: "text", text }],
    details
  };
}

const plugin = {
  id: metadata.id,
  name: metadata.displayName,
  version: metadata.version,
  description: metadata.description,
  register(api) {
    api.registerTool({
      name: metadata.toolName,
      label: metadata.displayName,
      description: "Use the " + metadata.displayName + " OpenClaw plugin. Actions: status, help.",
      parameters: ToolSchema,
      async execute(_toolCallId, params = {}) {
        const action = typeof params.action === "string" ? params.action : "status";
        if (action === "help") {
          const suffix = metadata.workflowCount === 1 ? "" : "s";
          return textResult(
            metadata.displayName + " is installed as an OpenClaw plugin. It includes " + metadata.workflowCount + " bundled workflow folder" + suffix + ". Live third-party API access may require plugin-specific authentication.",
            { action, workflowCount: metadata.workflowCount }
          );
        }

        return textResult(metadata.displayName + " OpenClaw plugin is loaded.", {
          action: "status",
          ready: true,
          workflowCount: metadata.workflowCount
        });
      }
    });
  }
};

export default plugin;
