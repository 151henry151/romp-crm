const JobPhotoViewer = {
  mounted() {
    this.stage = this.el.querySelector("[data-role=zoom-stage]")
    this.img = this.el.querySelector("[data-role=zoom-image]")
    this.scale = 1
    this.translateX = 0
    this.translateY = 0
    this.dragging = false
    this.lastX = 0
    this.lastY = 0
    this.pinchStartDistance = null
    this.pinchStartScale = 1

    this.applyTransform = () => {
      if (!this.img) return
      this.img.style.transform = `translate(${this.translateX}px, ${this.translateY}px) scale(${this.scale})`
    }

    this.resetZoom = () => {
      this.scale = 1
      this.translateX = 0
      this.translateY = 0
      this.applyTransform()
    }

    this.zoomBy = (delta) => {
      this.scale = Math.min(4, Math.max(1, this.scale + delta))
      if (this.scale === 1) {
        this.translateX = 0
        this.translateY = 0
      }
      this.applyTransform()
    }

    this.stage?.addEventListener(
      "wheel",
      (e) => {
        e.preventDefault()
        this.zoomBy(e.deltaY < 0 ? 0.15 : -0.15)
      },
      {passive: false}
    )

    this.stage?.addEventListener("dblclick", () => this.resetZoom())

    this.stage?.addEventListener("mousedown", (e) => {
      if (this.scale <= 1) return
      this.dragging = true
      this.lastX = e.clientX
      this.lastY = e.clientY
    })

    this.onMouseMove = (e) => {
      if (!this.dragging) return
      this.translateX += e.clientX - this.lastX
      this.translateY += e.clientY - this.lastY
      this.lastX = e.clientX
      this.lastY = e.clientY
      this.applyTransform()
    }

    this.onMouseUp = () => {
      this.dragging = false
    }

    window.addEventListener("mousemove", this.onMouseMove)
    window.addEventListener("mouseup", this.onMouseUp)

    this.stage?.addEventListener(
      "touchstart",
      (e) => {
        if (e.touches.length === 2) {
          e.preventDefault()
          this.pinchStartDistance = this.distance(e.touches[0], e.touches[1])
          this.pinchStartScale = this.scale
        } else if (e.touches.length === 1 && this.scale > 1) {
          this.dragging = true
          this.lastX = e.touches[0].clientX
          this.lastY = e.touches[0].clientY
        }
      },
      {passive: false}
    )

    this.stage?.addEventListener(
      "touchmove",
      (e) => {
        if (e.touches.length === 2 && this.pinchStartDistance) {
          e.preventDefault()
          const dist = this.distance(e.touches[0], e.touches[1])
          this.scale = Math.min(4, Math.max(1, this.pinchStartScale * (dist / this.pinchStartDistance)))
          if (this.scale === 1) {
            this.translateX = 0
            this.translateY = 0
          }
          this.applyTransform()
        } else if (e.touches.length === 1 && this.dragging && this.scale > 1) {
          e.preventDefault()
          this.translateX += e.touches[0].clientX - this.lastX
          this.translateY += e.touches[0].clientY - this.lastY
          this.lastX = e.touches[0].clientX
          this.lastY = e.touches[0].clientY
          this.applyTransform()
        }
      },
      {passive: false}
    )

    this.stage?.addEventListener("touchend", () => {
      this.pinchStartDistance = null
      this.dragging = false
    })

    this.handleEvent("photo-viewer-reset-zoom", () => {
      this.resetZoom()
    })

    this.onKeyDown = (e) => {
      if (e.key === "ArrowLeft") {
        e.preventDefault()
        this.pushEvent("photo_viewer_key", {key: "left"})
      } else if (e.key === "ArrowRight") {
        e.preventDefault()
        this.pushEvent("photo_viewer_key", {key: "right"})
      }
    }

    window.addEventListener("keydown", this.onKeyDown)
    this.lastPhotoId = this.el.dataset.photoId
  },

  updated() {
    const photoId = this.el.dataset.photoId
    if (photoId !== this.lastPhotoId) {
      this.lastPhotoId = photoId
      this.img = this.el.querySelector("[data-role=zoom-image]")
      this.resetZoom()
    }
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeyDown)
    window.removeEventListener("mousemove", this.onMouseMove)
    window.removeEventListener("mouseup", this.onMouseUp)
  },

  distance(a, b) {
    const dx = a.clientX - b.clientX
    const dy = a.clientY - b.clientY
    return Math.hypot(dx, dy)
  }
}

export default JobPhotoViewer
