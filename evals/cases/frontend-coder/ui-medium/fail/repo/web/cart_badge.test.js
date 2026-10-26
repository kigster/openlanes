import { render } from "./cart_badge.js";
test("renders the count", () => expect(render({ count: 2 })).toContain("2"));
test("shows the error", () => expect(render({ count: 0, error: "quantity must be at least 1" })).toContain('role="alert"'));
