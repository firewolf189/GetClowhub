import { defineToolPlugin } from "openclaw/plugin-sdk/tool-plugin";

const metadata = {
  id: "design-taste-frontend",
  displayName: "Design Taste Frontend",
  description: "Frontend design taste guidance for polished product UI decisions",
  version: "1.0.0",
  workflowCount: 1,
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
      name: "design_taste_frontend",
      description: "Check Design Taste Frontend plugin status or show bundled skill help.",
      parameters,
      execute: async ({ action = "status" } = {}) => {
        if (action === "help") {
          return {
            content: [
              {
                type: "text",
                text:
                  `${metadata.displayName} is installed as one OpenClaw plugin. ` +
                  "It includes the design-taste-frontend skill.",
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
