const ChatCompose = {
  mounted() {
    this.textarea = this.el.querySelector("textarea")
    if (!this.textarea) return

    this.onKeyDown = (event) => {
      if (event.key !== "Enter" || event.shiftKey) return
      if (this.textarea.disabled) return

      event.preventDefault()
      this.el.requestSubmit()
    }

    this.textarea.addEventListener("keydown", this.onKeyDown)
  },

  destroyed() {
    if (this.textarea && this.onKeyDown) {
      this.textarea.removeEventListener("keydown", this.onKeyDown)
    }
  }
}

export default ChatCompose
