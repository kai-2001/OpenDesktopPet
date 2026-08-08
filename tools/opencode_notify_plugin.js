// OpenDesktopPet OpenCode notification plugin
// OpenDesktopPet notification plugin for OpenCode's terminal interface.
// OpenCode loads this file from the global plugin directory.
import { join } from "node:path"
import { spawn } from "node:child_process"

const home = process.env.USERPROFILE || process.env.HOME || ""
const integrationHome = join(home, ".open-desktop-pet")
const bridgePath = join(integrationHome, "opencode_notify.ps1")

function invokeBridge(payload) {
  return new Promise((resolve) => {
    let child
    try {
      child = spawn("powershell.exe", [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-WindowStyle",
        "Hidden",
        "-File",
        bridgePath,
        payload,
      ], {
        stdio: "ignore",
        windowsHide: true,
      })
    } catch {
      resolve()
      return
    }

    child.once("error", () => resolve())
    child.once("close", () => resolve())
  })
}

export const OpenDesktopPetNotification = async () => ({
  event: async ({ event }) => {
    if (event?.type !== "session.idle" && event?.type !== "session.error") {
      return
    }

    const properties = event?.properties || {}
    const sessionId = properties.sessionID || properties.sessionId || ""
    const payload = JSON.stringify({
      type: event.type === "session.error" ? "agent-error" : "agent-turn-complete",
      session_id: sessionId,
      turn_id: properties.turnID || properties.turnId || "",
      cwd: process.cwd(),
    })

    try {
      await invokeBridge(payload)
    } catch {
      // Notification failures must never interrupt OpenCode.
    }
  },
})
