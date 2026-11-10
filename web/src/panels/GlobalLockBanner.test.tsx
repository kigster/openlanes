import { act, render, screen } from "@testing-library/react";
import { axe } from "vitest-axe";
import type { GlobalLock } from "../api/types";
import { countdown } from "./countdown";
import { GlobalLockBanner } from "./GlobalLockBanner";

const NOW = Date.parse("2026-11-08T12:00:00Z");

const lock = (over: Partial<GlobalLock> = {}): GlobalLock => ({
  plan: "031.00",
  slug: "rename-everything",
  title: "Rename Everything",
  taken_at: "2026-11-08T10:00:00Z",
  expires_at: "2026-11-09T10:00:00Z",
  ttl: 86_400,
  expired: false,
  waits_on: [],
  ...over,
});

const banner = () => screen.getByRole("region", { name: /Global lock/ });

describe("countdown", () => {
  it("drops the hours when there are none, pads the rest, and never goes negative", () => {
    expect(countdown(22 * 3600_000 + 4 * 60_000 + 9_000)).toBe("22h 04m 09s");
    expect(countdown(4 * 60_000 + 9_000)).toBe("4m 09s");
    expect(countdown(9_400)).toBe("9s");
    expect(countdown(-5_000)).toBe("0s");
  });
});

describe("GlobalLockBanner", () => {
  it("renders nothing when no refactor holds the lock", () => {
    const { container } = render(<GlobalLockBanner lock={null} now={NOW} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("names the refactor and counts down to when its lock lapses, accessibly", async () => {
    const { container } = render(<GlobalLockBanner lock={lock()} now={NOW} />);
    expect(banner()).toHaveTextContent("Global lock: refactor 031.00 Rename Everything");
    expect(banner()).toHaveTextContent("Nothing new starts until it merges.");
    expect(screen.getByRole("timer")).toHaveTextContent("22h 00m 00s");
    expect(banner()).toHaveAttribute("data-expired", "false");
    expect(await axe(container)).toHaveNoViolations();
  });

  it("says which plans the refactor's build still waits on", () => {
    render(<GlobalLockBanner lock={lock({ waits_on: ["018.00", "022.00"] })} now={NOW} />);
    expect(banner()).toHaveTextContent("Its build waits on 018.00, 022.00 to merge or close.");
  });

  it("gives the lock's length before the engine has recorded when it was taken", () => {
    render(<GlobalLockBanner lock={lock({ taken_at: null, expires_at: null, ttl: 5400 })} now={NOW} />);
    expect(banner()).toHaveTextContent("lapses 1.5 h after it is taken");
    expect(screen.queryByRole("timer")).toBeNull();
  });

  it("turns red once the lock has lapsed, by the engine's word or by the clock", () => {
    const { rerender } = render(<GlobalLockBanner lock={lock({ expired: true })} now={NOW} />);
    expect(banner()).toHaveAttribute("data-expired", "true");
    expect(banner()).toHaveTextContent("Global lock lapsed: refactor 031.00");
    expect(banner()).toHaveTextContent("Other plans start beside it again.");

    rerender(<GlobalLockBanner lock={lock({ expires_at: "2026-11-08T11:59:59Z" })} now={NOW} />);
    expect(banner()).toHaveAttribute("data-expired", "true");
    expect(screen.queryByRole("timer")).toBeNull();
  });

  it("ticks every second on its own clock", () => {
    vi.useFakeTimers({ now: NOW });
    try {
      render(<GlobalLockBanner lock={lock({ expires_at: "2026-11-08T12:00:05Z" })} />);
      expect(screen.getByRole("timer")).toHaveTextContent("5s");
      act(() => vi.advanceTimersByTime(2000));
      expect(screen.getByRole("timer")).toHaveTextContent("3s");
    } finally {
      vi.useRealTimers();
    }
  });
});
