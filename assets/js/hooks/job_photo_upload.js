const JobPhotoUpload = {
  mounted() {
    this.uploadUrl = this.el.dataset.uploadUrl
    this.galleryInput = this.el.querySelector("[data-role=gallery-input]")
    this.cameraInput = this.el.querySelector("[data-role=camera-input]")
    this.desktopCameraBtn = this.el.querySelector("[data-role=desktop-camera-btn]")
    this.webcamPanel = this.el.querySelector("[data-role=webcam-panel]")
    this.video = this.el.querySelector("[data-role=webcam-video]")
    this.canvas = this.el.querySelector("[data-role=webcam-canvas]")
    this.captureBtn = this.el.querySelector("[data-role=webcam-capture]")
    this.statusEl = this.el.querySelector("[data-role=status]")
    this.stream = null
    this.uploading = 0

    this.galleryInput?.addEventListener("change", (e) => this.onFilesSelected(e.target))
    this.cameraInput?.addEventListener("change", (e) => this.onFilesSelected(e.target))
    this.desktopCameraBtn?.addEventListener("click", () => this.openWebcam())
    this.captureBtn?.addEventListener("click", () => this.captureWebcamFrame())
  },

  destroyed() {
    this.stopWebcam()
  },

  setStatus(message, isError = false) {
    if (!this.statusEl) return
    this.statusEl.textContent = message || ""
    this.statusEl.classList.toggle("text-red-600", isError)
    this.statusEl.classList.toggle("text-gray-500", !isError)
  },

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
  },

  async onFilesSelected(input) {
    const files = Array.from(input.files || [])
    input.value = ""
    if (files.length === 0) return

    this.setStatus(`Uploading ${files.length} photo(s)…`)

    let saved = 0
    let lastError = null
    for (const file of files) {
      const result = await this.uploadFile(file)
      if (result.ok) {
        saved += 1
      } else {
        lastError = result.message
      }
    }

    if (saved > 0) {
      this.pushEvent("job_photo_uploaded", {count: saved})
      this.setStatus(
        saved === 1 ? "Photo saved." : `${saved} photos saved.`
      )
    } else {
      this.setStatus(lastError || "Could not save photo(s). Try again.", true)
      this.pushEvent("job_photo_upload_failed", {})
    }
  },

  async uploadFile(file) {
    this.uploading += 1
    const formData = new FormData()
    formData.append("photo", file, file.name || "photo.jpg")
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
        return {ok: true}
      }

      let message = "Could not save photo."
      if (response.status === 413) {
        message = "Photo is too large for upload (max 25 MB)."
      } else {
        try {
          const body = await response.json()
          if (body?.error) message = body.error
        } catch (_err) {
          // ignore non-json body
        }
      }

      return {ok: false, message}
    } catch (_err) {
      return {ok: false, message: "Network error while uploading."}
    } finally {
      this.uploading -= 1
    }
  },

  openWebcam() {
    if (this.webcamPanel) {
      this.webcamPanel.classList.remove("hidden")
    }
    this.startWebcam()
  },

  async startWebcam() {
    this.stopWebcam()

    if (!navigator.mediaDevices?.getUserMedia) {
      this.setStatus("Webcam not available — use Choose from gallery.", true)
      return
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {facingMode: "environment"},
        audio: false
      })
      this.video.srcObject = this.stream
      this.video.classList.remove("hidden")
      this.captureBtn?.classList.remove("hidden")
      this.setStatus("Aim the camera, then tap Capture photo.")
    } catch (_err) {
      this.setStatus("Could not open webcam — use Choose from gallery.", true)
    }
  },

  stopWebcam() {
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop())
      this.stream = null
    }
    if (this.video) {
      this.video.srcObject = null
      this.video.classList.add("hidden")
    }
    this.captureBtn?.classList.add("hidden")
  },

  captureWebcamFrame() {
    if (!this.video?.videoWidth) return

    this.canvas.width = this.video.videoWidth
    this.canvas.height = this.video.videoHeight
    const ctx = this.canvas.getContext("2d")
    ctx.drawImage(this.video, 0, 0)
    this.canvas.toBlob(
      async (blob) => {
        if (!blob) return
        const file = new File([blob], `capture-${Date.now()}.jpg`, {type: "image/jpeg"})
        this.setStatus("Uploading photo…")
        const result = await this.uploadFile(file)
        if (result.ok) {
          this.pushEvent("job_photo_uploaded", {count: 1})
          this.setStatus("Photo saved — capture another or tap Done.")
        } else {
          this.setStatus(result.message || "Could not save that photo.", true)
          this.pushEvent("job_photo_upload_failed", {})
        }
      },
      "image/jpeg",
      0.92
    )
  }
}

export default JobPhotoUpload
