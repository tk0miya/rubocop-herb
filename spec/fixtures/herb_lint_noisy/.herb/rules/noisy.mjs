// A custom rule that writes to stdout (console.log) to test that it does not break the protocol
export default class NoisyRule {
  static ruleName = "noisy";
  static type = "source";

  check(_source, _context) {
    console.log("noisy output from a custom rule");
    return [];
  }
}
