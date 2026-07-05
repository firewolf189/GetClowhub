import { defineToolPlugin } from "openclaw/plugin-sdk/tool-plugin";

const metadata = {
  id: "superpowers",
  displayName: "Superpowers",
  description: "Planning, TDD, debugging, and delivery workflows for coding agents",
  version: "6.1.0",
  workflowCount: 14,
};

const toolParameters = {
  type: "object",
  additionalProperties: false,
  properties: {
    action: {
      type: "string",
      enum: ["status", "help"],
      description: "Action to run.",
      default: "status",
    },
  },
};

export default defineToolPlugin({
  id: metadata.id,
  name: metadata.displayName,
  description: metadata.description,
  tools: (tool) => [
    tool({
      name: "superpowers",
      description: "Check the Superpowers plugin status or show bundled workflow help.",
      parameters: toolParameters,
      execute: async ({ action = "status" } = {}) => {
        if (action === "help") {
          const suffix = metadata.workflowCount === 1 ? "" : "s";
          return {
            content: [
              {
                type: "text",
                text:
                  `${metadata.displayName} is installed as one OpenClaw plugin. ` +
                  `It preserves the upstream Superpowers package and includes ${metadata.workflowCount} bundled skill workflow${suffix}.`,
              },
            ],
            workflowCount: metadata.workflowCount,
          };
        }

        return {
          content: [
            {
              type: "text",
              text: `${metadata.displayName} OpenClaw plugin is loaded.`,
            },
          ],
          ready: true,
          workflowCount: metadata.workflowCount,
        };
      },
    }),
  ],
});
