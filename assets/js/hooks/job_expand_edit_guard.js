const JobExpandEditGuard = {
  mounted() {
    this.initialSnapshot = null
    this.onClick = (e) => this.handleEditStartClick(e)
    this.el.addEventListener("click", this.onClick, true)
    this.syncSnapshot()
  },

  updated() {
    this.syncSnapshot()
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick, true)
  },

  syncSnapshot() {
    const form = this.activeEditForm()
    if (form) {
      this.initialSnapshot = this.snapshotForm(form)
    } else {
      this.initialSnapshot = null
    }
  },

  activeEditForm() {
    return this.el.querySelector("[data-job-expand-edit-form]")
  },

  activeEditSurface() {
    return this.el.querySelector("[data-job-expand-edit-surface]")
  },

  snapshotForm(form) {
    const data = new FormData(form)
    const snap = {}

    for (const [key, value] of data.entries()) {
      if (Object.prototype.hasOwnProperty.call(snap, key)) {
        const existing = snap[key]
        snap[key] = Array.isArray(existing) ? [...existing, value] : [existing, value]
      } else {
        snap[key] = value
      }
    }

    return snap
  },

  isDirty(form) {
    if (!this.initialSnapshot) return false
    return JSON.stringify(this.snapshotForm(form)) !== JSON.stringify(this.initialSnapshot)
  },

  handleEditStartClick(e) {
    const startBtn = e.target.closest("[data-job-expand-edit-start]")
    if (!startBtn) return

    const toKey = startBtn.dataset.jobExpandEditStart
    const activeForm = this.activeEditForm()
    const activeSurface = this.activeEditSurface()

    if (!activeForm && !activeSurface) return

    const activeKey =
      activeForm?.dataset.jobExpandEditKey || activeSurface?.dataset.jobExpandEditKey

    if (!activeKey || toKey === activeKey) return

    e.preventDefault()
    e.stopPropagation()

    const noDirty =
      activeSurface?.dataset.jobExpandNoDirty === "true" ||
      activeForm?.dataset.jobExpandNoDirty === "true"

    if (activeForm && !noDirty && this.isDirty(activeForm)) {
      this.flashActiveEdit(activeForm)
      return
    }

    this.pushEvent("job_expand_edit_switch", {to_key: toKey})
  },

  flashActiveEdit(form) {
    const actions = form.querySelector("[data-job-expand-edit-actions]")
    if (!actions) return

    actions.classList.remove("job-expand-edit-flash")
    void actions.offsetWidth
    actions.classList.add("job-expand-edit-flash")

    window.setTimeout(() => {
      actions.classList.remove("job-expand-edit-flash")
    }, 1800)
  }
}

export default JobExpandEditGuard
