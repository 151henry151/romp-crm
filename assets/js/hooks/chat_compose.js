const ChatCompose = {
  mounted() {
    this.textarea = this.el.querySelector("textarea")
    this.fileInput = this.el.querySelector("[data-role=chat-attach-input]")
    this.statusEl = this.el.querySelector("[data-role=chat-attach-status]")
    this.uploadUrl = this.el.dataset.uploadUrl || ""
    this.attachEnabled = this.el.dataset.attachEnabled === "true"

    // phone is on the upload URL query string; also append for POST body
    try {
      const u = new URL(this.uploadUrl, window.location.origin)
      this.phone = u.searchParams.get("phone") || ""
    } catch (_err) {
      this.phone = ""
    }

    this.onKeyDown = (event) => {
      if (event.key !== "Enter" || event.shiftKey) return
      if (this.textarea?.disabled) return

      event.preventDefault()
      this.el.requestSubmit()
    }

    this.textarea?.addEventListener("keydown", this.onKeyDown)
    this.fileInput?.addEventListener("change", (e) => this.onFilesSelected(e.target))
  },

  destroyed() {
    if (this.textarea && this.onKeyDown) {
      this.textarea.removeEventListener("keydown", this.onKeyDown)
    }
  },

  setStatus(message, isError = false) {
    if (!this.statusEl) return
    this.statusEl.textContent = message || ""
    this.statusEl.classList.toggle("text-red-600", isError)
    this.statusEl.classList.toggle("text-base-content/60", !isError)
  },

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
  },

  async onFilesSelected(input) {
    const files = Array.from(input.files || [])
    input.value = ""
    if (files.length === 0) return
    if (!this.attachEnabled || !this.uploadUrl) return

    this.setStatus(`Uploading ${files.length} photo(s)…`)

    let saved = 0
    let lastError = null
    for (const file of files) {
      const result = await this.uploadFile(file)
      if (result.ok) {
        saved += 1
        this.pushEvent("chat_media_uploaded", {url: result.url})
      } else {
        lastError = result.message
      }
    }

    if (saved > 0) {
      this.setStatus(saved === 1 ? "Photo attached." : `${saved} photos attached.`)
    } else {
      this.setStatus(lastError || "Could not attach photo(s).", true)
    }
  },

  async uploadFile(file) {
    const formData = new FormData()
    formData.append("photo", file, file.name || "photo.jpg")
    if (this.phone) formData.append("phone", this.phone)
    const csrf = this.csrfToken()
    if (csrf) formData.append("_csrf_token", csrf)

    try {
      const response = await fetch(this.uploadUrl, {
        method: "POST",
        headers: {
          "X-Photo-Upload": "1",
          ...(csrf ? {"x-csrf-token": csrf} : {})
        },
        body: formData,
        credentials: "same-origin"
      })

      if (response.ok) {
        const body = await response.json()
        if (body?.url) return {ok: true, url: body.url}
        return {ok: false, message: "Upload succeeded but no URL returned."}
      }

      let message = "Could not attach photo."
      if (response.status === 413) {
        message = "Photo is too large (max 5 MB)."
      } else {
        try {
          const body = await response.json()
          if (body?.error) message = body.error
        } catch (_err) {
          // ignore
        }
      }

      return {ok: false, message}
    } catch (_err) {
      return {ok: false, message: "Network error while uploading."}
    }
  }
}

export default ChatCompose
