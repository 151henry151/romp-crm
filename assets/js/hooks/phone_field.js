const PhoneField = {
  mounted() {
    this.bind()
  },

  updated() {
    this.bind()
  },

  bind() {
    this.unbind()

    this.stored = this.el.querySelector("[data-phone-stored]")
    this.dial = this.el.querySelector("[data-phone-dial]")
    this.national = this.el.querySelector("[data-phone-national]")
    if (!this.stored || !this.dial || !this.national) return

    this.onDialChange = () => {
      this.updatePlaceholder()
      this.syncStored()
    }

    this.onNationalInput = () => {
      if (this.dial.value === "1") {
        this.national.value = formatNanp(this.national.value)
      }
      this.syncStored()
    }

    this.dial.addEventListener("change", this.onDialChange)
    this.national.addEventListener("input", this.onNationalInput)

    const form = this.el.closest("form")
    if (form) {
      this.onSubmit = () => this.syncStored()
      form.addEventListener("submit", this.onSubmit, true)
    }

    this.syncStored()
  },

  unbind() {
    this.dial?.removeEventListener("change", this.onDialChange)
    this.national?.removeEventListener("input", this.onNationalInput)
    const form = this.el.closest("form")
    if (form && this.onSubmit) {
      form.removeEventListener("submit", this.onSubmit, true)
    }
  },

  updatePlaceholder() {
    this.national.placeholder =
      this.dial.value === "1" ? "(555) 555-1234" : "Phone number"
  },

  syncStored() {
    const dial = this.dial.value.replace(/\D/g, "")
    const national = this.national.value.replace(/\D/g, "")

    if (!national) {
      this.stored.value = ""
    } else {
      this.stored.value = `+${dial}${national}`
    }

    this.stored.dispatchEvent(new Event("input", {bubbles: true}))
    this.stored.dispatchEvent(new Event("change", {bubbles: true}))
  }
}

function formatNanp(raw) {
  const digits = raw.replace(/\D/g, "").slice(0, 10)
  if (digits.length <= 3) return digits
  if (digits.length <= 6) return `(${digits.slice(0, 3)}) ${digits.slice(3)}`
  return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`
}

export default PhoneField
