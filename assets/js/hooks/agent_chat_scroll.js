const AgentChatScroll = {
  mounted() {
    this.scrollToBottom()

    this.handleEvent("chat-scroll-bottom", () => {
      this.scrollToBottom()
    })
  },

  updated() {
    this.scrollToBottom()
  },

  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

export default AgentChatScroll
