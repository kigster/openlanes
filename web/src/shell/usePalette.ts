// The page's colours. "auto" follows the operating system between the built-in light and dark; every other choice
// is pinned. A choice is this viewer's own, kept in localStorage, and applied by two attributes on <html>:
// data-theme, the scheme everything already keys off, and data-palette, which styles/palettes.css reads.
import { useCallback, useState } from "react";

export const PALETTE_KEY = "openlanes-palette";

export interface Palette {
  id: string;
  name: string;
  note: string;
  /** Left unset on <html> for "auto", so the system's preference decides. */
  scheme: "light" | "dark" | null;
  /** Page, panel and accent, for the menu's swatch. Null for "auto", which has no colours of its own. */
  swatch: [string, string, string] | null;
}

export const PALETTES: Palette[] = [
  { id: "auto", name: "System", note: "Daylight or Midnight, as your computer says", scheme: null, swatch: null },
  { id: "light", name: "Daylight", note: "Light: cool grey and navy", scheme: "light", swatch: ["#E9EDF1", "#FFFFFF", "#1F5FD1"] },
  { id: "paper", name: "Paper", note: "Light: cream panels, warm text", scheme: "light", swatch: ["#F8F8F8", "#FFF3DC", "#D35728"] },
  { id: "earth", name: "Earth", note: "Light: parchment and umber", scheme: "light", swatch: ["#F7F1DE", "#ECE2C4", "#9D4F1C"] },
  { id: "forest", name: "Forest", note: "Light: mint and deep green", scheme: "light", swatch: ["#A9ECD8", "#C9F3E6", "#C7003F"] },
  { id: "dark", name: "Midnight", note: "Dark: deep navy", scheme: "dark", swatch: ["#0E1522", "#151E2F", "#5B8DF0"] },
  { id: "ember", name: "Ember", note: "Dark: black-brown and hot orange", scheme: "dark", swatch: ["#140C02", "#1D1305", "#FF5F00"] },
  { id: "azure", name: "Azure", note: "Dark: slate blue and sand", scheme: "dark", swatch: ["#2D3C59", "#26334D", "#E5BA41"] },
];

const find = (id: string | null | undefined): Palette => PALETTES.find(p => p.id === id) ?? PALETTES[0];

function stored(): Palette {
  try {
    return find(localStorage.getItem(PALETTE_KEY));
  } catch {
    return PALETTES[0]; // a private window: the system's
  }
}

/** Puts a palette on <html>. The built-in two need no data-palette: their colours are the scheme's own. */
export function applyPalette(palette: Palette): void {
  const { dataset } = document.documentElement;
  if (palette.scheme) dataset.theme = palette.scheme;
  else delete dataset.theme;
  if (palette.id === "auto" || palette.id === "light" || palette.id === "dark") delete dataset.palette;
  else dataset.palette = palette.id;
}

/** Applies the stored choice. Called once before the first render, so the page never flashes the wrong colours. */
export function restorePalette(): void {
  applyPalette(stored());
}

export function usePalette(): { palette: Palette; choose: (id: string) => void } {
  const [palette, setPalette] = useState<Palette>(stored);
  const choose = useCallback((id: string) => {
    const next = find(id);
    applyPalette(next);
    setPalette(next);
    try {
      localStorage.setItem(PALETTE_KEY, next.id);
    } catch {
      // a private window: the choice lasts for this visit only
    }
  }, []);
  return { palette, choose };
}
