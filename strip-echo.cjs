try {
  if (process && process.env) {
    if (typeof process.env.CHAT_ECHO !== 'undefined') {
      process.env.CHAT_ECHO = '';
    }
  }
} catch {}