import { describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import { ColumnDivider } from "./ColumnDivider";

function setup() {
  const layout = document.createElement("div");
  layout.getBoundingClientRect = () => ({ right: 1000, left: 0, top: 0, bottom: 0, width: 1000, height: 0, x: 0, y: 0, toJSON() {} });
  const props = { width: 400, min: 360, max: 600, onResize: vi.fn(), onNudge: vi.fn(), onReset: vi.fn(), layoutRef: { current: layout } };
  render(<ColumnDivider {...props} />);
  return { props, sep: screen.getByRole("separator") };
}

describe("ColumnDivider", () => {
  it("exposes its value and bounds", () => {
    const { sep } = setup();
    expect(sep).toHaveAttribute("aria-orientation", "vertical");
    expect(sep).toHaveAttribute("aria-label", "Resize side panel");
    expect(sep).toHaveAttribute("aria-valuenow", "400");
    expect(sep).toHaveAttribute("aria-valuemin", "360");
    expect(sep).toHaveAttribute("aria-valuemax", "600");
    expect(sep).toHaveAttribute("tabindex", "0");
  });

  it("drags without a jump at pointerdown", () => {
    const { props, sep } = setup();
    sep.setPointerCapture = vi.fn();
    sep.releasePointerCapture = vi.fn();
    // The column's left edge is 600; grabbing at 590 must leave the width at 400, then 50px left makes it 450.
    fireEvent.pointerDown(sep, { clientX: 590, button: 0, pointerId: 1 });
    expect(sep.setPointerCapture).toHaveBeenCalledWith(1);
    fireEvent.pointerMove(sep, { clientX: 590, pointerId: 1 });
    expect(props.onResize).toHaveBeenLastCalledWith(400);
    fireEvent.pointerMove(sep, { clientX: 540, pointerId: 1 });
    expect(props.onResize).toHaveBeenLastCalledWith(450);
    fireEvent.pointerUp(sep, { clientX: 540, pointerId: 1 });
    expect(sep.releasePointerCapture).toHaveBeenCalledWith(1);
    props.onResize.mockClear();
    fireEvent.pointerMove(sep, { clientX: 100, pointerId: 1 });
    expect(props.onResize).not.toHaveBeenCalled();
  });

  it("ignores a non-primary button and a move with no grab", () => {
    const { props, sep } = setup();
    fireEvent.pointerDown(sep, { clientX: 590, button: 2 });
    fireEvent.pointerMove(sep, { clientX: 500 });
    fireEvent.pointerUp(sep);
    expect(props.onResize).not.toHaveBeenCalled();
  });

  it("widens on ArrowLeft, narrows on ArrowRight, resets on Home", () => {
    const { props, sep } = setup();
    fireEvent.keyDown(sep, { key: "ArrowLeft" });
    expect(props.onNudge).toHaveBeenLastCalledWith(24);
    fireEvent.keyDown(sep, { key: "ArrowRight" });
    expect(props.onNudge).toHaveBeenLastCalledWith(-24);
    fireEvent.keyDown(sep, { key: "Home" });
    expect(props.onReset).toHaveBeenCalledTimes(1);
    fireEvent.keyDown(sep, { key: "a" });
    expect(props.onNudge).toHaveBeenCalledTimes(2);
  });

  it("resets on double-click", () => {
    const { props, sep } = setup();
    fireEvent.doubleClick(sep);
    expect(props.onReset).toHaveBeenCalledTimes(1);
  });
});
