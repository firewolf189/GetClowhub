import { defineToolPlugin } from "openclaw/plugin-sdk/tool-plugin";

const metadata = {
  id: "openspec",
  displayName: "OpenSpec",
  description: "Structured proposal, planning, implementation, and archive workflows for OpenSpec changes",
  version: "1.0.0",
  workflowCount: 4,
};

const parameters = {
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
      name: "openspec",
      description: "Check OpenSpec plugin status or show bundled workflow help.",
      parameters,
      execute: async ({ action = "status" } = {}) => {
        if (action === "help") {
          return {
            content: [
              {
                type: "text",
                text:
                  `${metadata.displayName} is installed as one OpenClaw plugin. ` +
                  "It includes explore, propose, apply-change, and archive-change skills.",
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
