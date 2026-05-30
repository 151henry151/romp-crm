const BillingAddressToggle = {
  mounted() {
    this.bind()
  },

  updated() {
    this.bind()
  },

  destroyed() {
    this.unbind()
  },

  bind() {
    this.unbind()

    this.checkbox = this.el.querySelector("[data-billing-toggle]")
    this.panel = this.el.querySelector("[data-billing-panel]")
    if (!this.checkbox || !this.panel) return

    this.onChange = () => {
      this.syncPanel()
    }

    this.checkbox.addEventListener("change", this.onChange)
    this.syncPanel()
  },

  syncPanel() {
    if (!this.checkbox || !this.panel) return
    this.panel.classList.toggle("hidden", !this.checkbox.checked)
  },

  unbind() {
    if (this.checkbox && this.onChange) {
      this.checkbox.removeEventListener("change", this.onChange)
    }
  }
}

export default BillingAddressToggle
