import { readFileSync } from "node:fs";
import { act, renderHook } from "@testing-library/react";
import { stubMedia } from "../test/media";
import { PHONE_MAX_WIDTH, PHONE_QUERY, usePhone } from "./usePhone";

afterEach(() => vi.unstubAllGlobals());

it("is not a phone where nothing matches, or where there is no matchMedia at all", () => {
  const stubbed = renderHook(() => usePhone()).result.current;
  vi.stubGlobal("matchMedia", undefined);
  expect([stubbed, renderHook(() => usePhone()).result.current]).toEqual([false, false]);
});

it("asks about its own query and follows the viewport across the line", () => {
  let width = 390;
  const asked: string[] = [];
  const media = stubMedia(query => {
    asked.push(query);
    return width <= PHONE_MAX_WIDTH;
  });
  const { result, unmount } = renderHook(() => usePhone());
  const narrow = result.current;
  width = 1280;
  act(() => media.change());
  expect([narrow, result.current, new Set(asked)]).toEqual([true, false, new Set([PHONE_QUERY])]);
  unmount();
  width = 390;
  media.change(); // nobody is listening any more
  expect(result.current).toBe(false);
});

// CSS cannot read the constant, so the stylesheets repeat it. A phone block at any other width would lay the page
// out one way while the script (the hide-nav button, the repeating chime) behaved the other.
it("is the one width the stylesheet's phone blocks use", () => {
  const css = readFileSync("src/shell/shell.css", "utf8");
  const phoneBlocks = css.match(/@media \(max-width: 600px\)/g) ?? [];
  expect([PHONE_QUERY, phoneBlocks.length]).toEqual(["(max-width: 600px)", 2]);
});
