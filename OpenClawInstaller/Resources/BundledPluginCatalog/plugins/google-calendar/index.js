const skillNames = [
  "google-calendar",
  "google-calendar-daily-brief",
  "google-calendar-free-up-time",
  "google-calendar-group-scheduler",
  "google-calendar-meeting-prep",
];

const helpText = `Google Calendar OpenClaw adapter is installed.

This adapter exposes the upstream Codex plugin guidance to OpenClaw and provides a stable tool entrypoint.

Available actions:
- status: confirm that the adapter is loaded
- help: list bundled Google Calendar skill workflows

Live Google Calendar event read/write requires an OAuth-backed runtime adapter.`;

const GoogleCalendarToolSchema = {
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

function textResult(text, details = {}) {
  return {
    content: [{ type: "text", text }],
    details,
  };
}

const plugin = {
  id: "google-calendar",
  name: "Google Calendar",
  description: "OpenClaw adapter for the Google Calendar Codex plugin package.",
  register(api) {
    api.registerTool({
      name: "google_calendar",
      label: "Google Calendar",
      description:
        "Use the Google Calendar adapter. Actions: status, help. Live calendar API access requires OAuth configuration.",
      parameters: GoogleCalendarToolSchema,
      async execute(_toolCallId, params = {}) {
        const action = typeof params.action === "string" ? params.action : "status";
        if (action === "help") {
          return textResult(
            `${helpText}\n\nBundled skill workflows:\n${skillNames.map((name) => `- ${name}`).join("\n")}`,
            { action, skills: skillNames },
          );
        }

        return textResult("Google Calendar OpenClaw adapter is loaded.", {
          action: "status",
          ready: true,
          liveCalendarApi: false,
          skills: skillNames,
        });
      },
    });
  },
};

export default plugin;
