// A post-format rewriter prepending a comment to the formatted source unless it has the comment
// (idempotent as rewriters should be, as the formatter runs on its output again).
// Rewriters are detected by the name of their base class, so it does not depend on @herb-tools/rewriter
class StringRewriter {
  async initialize() {}
}

export default class PrependComment extends StringRewriter {
  get name() {
    return "prepend-comment";
  }

  get description() {
    return "Prepends a comment to the formatted source";
  }

  rewrite(formatted) {
    const comment = "<%# formatted %>\n";
    return formatted.startsWith(comment) ? formatted : `${comment}${formatted}`;
  }
}
