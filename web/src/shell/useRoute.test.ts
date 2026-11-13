import { act, renderHook } from "@testing-library/react";
import { routeOf, useRoute } from "./useRoute";

afterEach(() => window.history.replaceState(null, "", "/"));

it("reads the page from the path", () => {
  expect(routeOf("/dependencies")).toBe("/dependencies");
  expect(routeOf("/dependencies/")).toBe("/dependencies");
  expect(routeOf("/settings")).toBe("/settings");
  expect(routeOf("/settings/")).toBe("/settings");
  expect(routeOf("/anything")).toBe("/");
});

it("navigates with pushState and follows Back", () => {
  const { result } = renderHook(() => useRoute());
  act(() => result.current.navigate("/dependencies"));
  expect(window.location.pathname).toBe("/dependencies");
  expect(result.current.route).toBe("/dependencies");
  act(() => {
    window.history.pushState(null, "", "/");
    window.dispatchEvent(new PopStateEvent("popstate"));
  });
  expect(result.current.route).toBe("/");
});

it("does not push the page it is already on", () => {
  const { result } = renderHook(() => useRoute());
  const before = window.history.length;
  act(() => result.current.navigate("/"));
  expect(window.history.length).toBe(before);
});
