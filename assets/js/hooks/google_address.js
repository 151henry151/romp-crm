const GoogleAddress = {
  mounted() {
    this._debounceTimers = new Map()
    this._requestIds = new Map()
    this._sessionTokens = new Map()
    this._lists = new Set()
    this._listByInput = new Map()
    this._suppressFetchUntil = new Map()
    this._outsideClick = (e) => this.onDocumentClick(e)

    this.initPlaces()
    document.addEventListener("click", this._outsideClick)

    this.handleEvent("address_fill", ({part, fields}) => {
      this.setPartFields(part, fields)
    })
  },

  destroyed() {
    document.removeEventListener("click", this._outsideClick)
    this._lists.forEach((list) => list.remove())
    this._lists.clear()
    this._listByInput.clear()
  },

  updated() {
    this.initPlaces()
  },

  async initPlaces() {
    await this.waitForGoogle()
    if (!window.google?.maps?.importLibrary) return

    if (!this._placesLib) {
      this._placesLib = await google.maps.importLibrary("places")
    }

    this.el.querySelectorAll("[data-address-autocomplete]").forEach((input) => {
      if (input.dataset.acBound === "true") return
      input.dataset.acBound = "true"
      this.bindAutocomplete(input)
    })
  },

  bindAutocomplete(input) {
    const part = input.dataset.addressPart
    const list = this.ensureSuggestionList(input)

    input.addEventListener("input", () => {
      if (this.fetchSuppressed(part)) return
      this.debounce(part, () => this.fetchSuggestions(input, list, part))
    })

    input.addEventListener("focus", () => {
      if (this.fetchSuppressed(part)) return
      if (input.value.trim().length >= 2) {
        this.fetchSuggestions(input, list, part)
      }
    })

    input.addEventListener("keydown", (e) => {
      if (e.key === "Escape") this.hideSuggestions(list)
    })
  },

  fetchSuppressed(part) {
    const until = this._suppressFetchUntil.get(part) || 0
    return Date.now() < until
  },

  suppressFetch(part, ms = 400) {
    this._suppressFetchUntil.set(part, Date.now() + ms)
  },

  ensureSuggestionList(input) {
    const key = input.id || input.name
    if (this._listByInput.has(key)) return this._listByInput.get(key)

    const wrap = input.closest("[data-address-autocomplete-wrap]") || input.parentElement
    wrap.classList.add("relative")

    const list = document.createElement("ul")
    list.dataset.addressSuggestions = "true"
    list.className =
      "address-suggestions hidden fixed z-[9999] max-h-56 overflow-y-auto rounded-md border border-base-300 bg-base-100 py-1 text-sm shadow-lg"
    list.setAttribute("role", "listbox")
    document.body.appendChild(list)
    this._lists.add(list)
    this._listByInput.set(key, list)
    return list
  },

  positionSuggestionList(list, input) {
    const rect = input.getBoundingClientRect()
    list.style.top = `${rect.bottom + 4}px`
    list.style.left = `${rect.left}px`
    list.style.width = `${Math.max(rect.width, 200)}px`
  },

  debounce(part, fn) {
    clearTimeout(this._debounceTimers.get(part))
    this._debounceTimers.set(part, setTimeout(fn, 220))
  },

  cancelPendingFetch(part) {
    clearTimeout(this._debounceTimers.get(part))
    this._requestIds.set(part, (this._requestIds.get(part) || 0) + 1)
  },

  async fetchSuggestions(input, list, part) {
    if (this.fetchSuppressed(part)) return

    const query = input.value.trim()
    if (query.length < 2) {
      this.hideSuggestions(list)
      return
    }

    const {AutocompleteSuggestion, AutocompleteSessionToken} = this._placesLib

    if (!this._sessionTokens.has(part)) {
      this._sessionTokens.set(part, new AutocompleteSessionToken())
    }

    const requestId = (this._requestIds.get(part) || 0) + 1
    this._requestIds.set(part, requestId)

    try {
      const {suggestions} = await AutocompleteSuggestion.fetchAutocompleteSuggestions({
        input: query,
        includedRegionCodes: ["us"],
        sessionToken: this._sessionTokens.get(part)
      })

      if (this._requestIds.get(part) !== requestId || this.fetchSuppressed(part)) return

      this.renderSuggestions(list, input, part, suggestions || [])
    } catch (err) {
      console.warn("Address autocomplete request failed", err)
      this.hideSuggestions(list)
    }
  },

  renderSuggestions(list, input, part, suggestions) {
    list.replaceChildren()

    const predictions = suggestions
      .map((s) => s.placePrediction)
      .filter(Boolean)

    if (predictions.length === 0) {
      this.hideSuggestions(list)
      return
    }

    predictions.forEach((prediction) => {
      const li = document.createElement("li")
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className =
        "block w-full px-3 py-2 text-left text-base-content hover:bg-base-200 focus:bg-base-200 focus:outline-none"
      btn.textContent = prediction.text?.toString() || ""
      btn.addEventListener("mousedown", (e) => {
        // Keep focus on the address input; do not tear down the list before selection runs.
        e.preventDefault()
      })
      btn.addEventListener("pointerdown", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.selectPrediction(input, list, part, prediction)
      })
      li.appendChild(btn)
      list.appendChild(li)
    })

    this.positionSuggestionList(list, input)
    list.dataset.activeInputId = input.id || ""
    list.classList.remove("hidden")
  },

  async selectPrediction(input, list, part, prediction) {
    if (list.dataset.selecting === "true") return
    list.dataset.selecting = "true"

    this.cancelPendingFetch(part)
    this.suppressFetch(part)

    try {
      const place = prediction.toPlace()
      await place.fetchFields({
        fields: ["addressComponents", "formattedAddress", "postalAddress"]
      })

      let parsed = this.parseComponents(place.addressComponents || [])

      if (!parsed.line1) {
        parsed = this.mergeParsed(parsed, this.parsePostalAddress(place.postalAddress))
      }

      if (!parsed.line1) {
        parsed = this.mergeParsed(parsed, this.parseFormattedAddress(place.formattedAddress))
      }

      if (parsed.line1) input.value = parsed.line1
      this.setPartFields(part, parsed)
    } catch (err) {
      console.warn("Address place fetch failed", err)
    } finally {
      delete list.dataset.selecting
      this._sessionTokens.set(part, new this._placesLib.AutocompleteSessionToken())
      this.hideSuggestions(list)
    }
  },

  hideSuggestions(list) {
    list.classList.add("hidden")
    list.replaceChildren()
    delete list.dataset.activeInputId
    delete list.dataset.selecting
  },

  onDocumentClick(e) {
    this._lists.forEach((list) => {
      const inputId = list.dataset.activeInputId
      const input = inputId ? document.getElementById(inputId) : null
      if (!list.contains(e.target) && e.target !== input) {
        this.hideSuggestions(list)
      }
    })
  },

  setPartFields(part, fields) {
    Object.entries({
      line1: fields.line1 || fields.address_line1 || fields.billing_address_line1,
      line2: fields.line2 || fields.address_line2 || fields.billing_address_line2,
      city: fields.city || fields.billing_city,
      state: fields.state || fields.billing_state,
      postal_code: fields.postal_code || fields.billing_postal_code
    }).forEach(([field, value]) => {
      const el = this.el.querySelector(
        `[data-address-part="${part}"][data-address-field="${field}"]`
      )
      if (el) {
        el.value = value || ""
        el.dispatchEvent(new Event("input", {bubbles: true}))
      }
    })
  },

  parseComponents(components) {
    const acc = {line1: "", line2: "", city: "", state: "", postal_code: ""}

    components.forEach((component) => {
      const types = component.types || []
      const long = this.componentText(component.longText ?? component.long_name)
      const short = this.componentText(component.shortText ?? component.short_name)

      if (types.includes("street_number")) acc.street_number = long
      if (types.includes("route")) acc.route = long
      if (types.includes("subpremise")) acc.line2 = long
      if (types.includes("locality")) acc.city = long
      if (types.includes("postal_town") && !acc.city) acc.city = long
      if (types.includes("administrative_area_level_1")) acc.state = short
      if (types.includes("postal_code")) acc.postal_code = long
    })

    acc.line1 = [acc.street_number, acc.route].filter(Boolean).join(" ")
    delete acc.street_number
    delete acc.route
    return acc
  },

  parsePostalAddress(postalAddress) {
    if (!postalAddress || typeof postalAddress !== "object") return {}

    return {
      line1: this.componentText(postalAddress.addressLines?.[0]),
      line2: this.componentText(postalAddress.addressLines?.[1]),
      city: this.componentText(postalAddress.locality),
      state: this.componentText(postalAddress.administrativeArea),
      postal_code: this.componentText(postalAddress.postalCode)
    }
  },

  parseFormattedAddress(formatted) {
    const text = this.componentText(formatted)
    if (!text) return {}

    const parts = text.split(",").map((p) => p.trim())
    if (parts.length === 0) return {}

    const last = parts[parts.length - 1] || ""
    const stateZip = last.match(/^([A-Za-z]{2})\s+(\d{5}(?:-\d{4})?)$/)

    return {
      line1: parts[0] || "",
      city: parts.length > 2 ? parts[parts.length - 2] : "",
      state: stateZip ? stateZip[1] : "",
      postal_code: stateZip ? stateZip[2] : ""
    }
  },

  mergeParsed(base, extra) {
    return {
      line1: base.line1 || extra.line1 || "",
      line2: base.line2 || extra.line2 || "",
      city: base.city || extra.city || "",
      state: base.state || extra.state || "",
      postal_code: base.postal_code || extra.postal_code || ""
    }
  },

  componentText(value) {
    if (value == null) return ""
    if (typeof value === "string") return value

    if (typeof value === "object") {
      if (typeof value.text === "string") return value.text
      if (typeof value.toString === "function") {
        const s = value.toString()
        if (s && s !== "[object Object]") return s
      }
    }

    return ""
  },

  waitForGoogle() {
    return new Promise((resolve) => {
      const deadline = Date.now() + 10000

      const check = () => {
        if (window.google?.maps?.importLibrary) {
          resolve()
        } else if (Date.now() > deadline) {
          resolve()
        } else {
          setTimeout(check, 50)
        }
      }

      check()
    })
  }
}

export default GoogleAddress
