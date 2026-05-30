const GoogleAddress = {
  mounted() {
    this.prefix = this.el.dataset.prefix || "job"
    this.loadMaps().then(() => this.initAutocomplete())

    this.el.querySelectorAll("[data-address-validate]").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.preventDefault()
        const part = btn.dataset.addressValidate
        this.pushAddressEvent("address_validate", this.gatherPart(part))
      })
    })

    this.handleEvent("address_fill", ({part, fields}) => {
      this.setPartFields(part, fields)
    })
  },

  pushAddressEvent(event, payload) {
    const target = this.el.getAttribute("phx-target")

    if (target) {
      this.pushEventTo(target, event, payload)
    } else {
      this.pushEvent(event, payload)
    }
  },

  updated() {
    this.initAutocomplete()
  },

  gatherPart(part) {
    const root = this.el
    const pick = (field) => {
      const input = root.querySelector(`[data-address-part="${part}"][data-address-field="${field}"]`)
      return input ? input.value : ""
    }

    const payload = {
      part,
      address_line1: pick("line1"),
      address_line2: pick("line2"),
      city: pick("city"),
      state: pick("state"),
      postal_code: pick("postal_code")
    }

    if (part === "billing") {
      return {
        part,
        billing_address_line1: payload.address_line1,
        billing_address_line2: payload.address_line2,
        billing_city: payload.city,
        billing_state: payload.state,
        billing_postal_code: payload.postal_code
      }
    }

    return payload
  },

  setPartFields(part, fields) {
    const map =
      part === "billing"
        ? {
            line1: fields.billing_address_line1,
            line2: fields.billing_address_line2,
            city: fields.billing_city,
            state: fields.billing_state,
            postal_code: fields.billing_postal_code
          }
        : fields

    Object.entries({
      line1: map.address_line1 || map.line1,
      line2: map.address_line2 || map.line2,
      city: map.city,
      state: map.state,
      postal_code: map.postal_code
    }).forEach(([field, value]) => {
      const input = this.el.querySelector(
        `[data-address-part="${part}"][data-address-field="${field}"]`
      )
      if (input) input.value = value || ""
    })
  },

  initAutocomplete() {
    if (!window.google?.maps?.places) return

    this.el.querySelectorAll("[data-address-autocomplete]").forEach((input) => {
      if (input._googleAutocomplete) return

      const part = input.dataset.addressPart
      const autocomplete = new google.maps.places.Autocomplete(input, {
        componentRestrictions: {country: "us"},
        fields: ["address_components", "formatted_address"],
        types: ["address"]
      })

      autocomplete.addListener("place_changed", () => {
        const place = autocomplete.getPlace()
        if (!place?.address_components) return

        const parsed = this.parseComponents(place.address_components)
        this.setPartFields(part, parsed)
      })

      input._googleAutocomplete = autocomplete
    })
  },

  parseComponents(components) {
    const acc = {line1: "", line2: "", city: "", state: "", postal_code: ""}

    components.forEach((component) => {
      const name = component.long_name
      const types = component.types

      if (types.includes("street_number")) acc.street_number = name
      if (types.includes("route")) acc.route = name
      if (types.includes("subpremise")) acc.line2 = name
      if (types.includes("locality")) acc.city = name
      if (types.includes("administrative_area_level_1")) acc.state = component.short_name
      if (types.includes("postal_code")) acc.postal_code = name
    })

    acc.line1 = [acc.street_number, acc.route].filter(Boolean).join(" ")
    delete acc.street_number
    delete acc.route
    return acc
  },

  loadMaps() {
    const key = document.querySelector("meta[name='google-maps-api-key']")?.content
    if (!key) return Promise.resolve()

    if (window.google?.maps?.places) return Promise.resolve()

    return new Promise((resolve) => {
      const script = document.createElement("script")
      script.src = `https://maps.googleapis.com/maps/api/js?key=${key}&libraries=places`
      script.async = true
      script.onload = () => resolve()
      document.head.appendChild(script)
    })
  }
}

export default GoogleAddress
