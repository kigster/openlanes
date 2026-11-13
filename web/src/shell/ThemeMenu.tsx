// The header's theme button: a menu of palettes, each with a swatch of its page, panel and accent colours.
import * as DropdownMenu from "@radix-ui/react-dropdown-menu";
import { PALETTES, usePalette, type Palette } from "./usePalette";

const ICON = (
  <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round">
    <path d="M12 3a9 9 0 1 0 0 18c1.4 0 2-1 2-2 0-1.6-1.2-1.8-1.2-3 0-1 .8-1.6 2-1.6H17a4 4 0 0 0 4-4c0-4.2-4-7.4-9-7.4z" />
    <circle cx="7.5" cy="12" r="1" /><circle cx="9.5" cy="8" r="1" /><circle cx="14" cy="7" r="1" />
  </svg>
);

function Swatch({ palette }: { palette: Palette }) {
  const [page, panel, accent] = palette.swatch;
  return (
    <span className="swatch" aria-hidden="true" style={{ background: page }}>
      <span style={{ background: panel }} />
      <span style={{ background: accent }} />
    </span>
  );
}

export function ThemeMenu() {
  const { palette, choose } = usePalette();
  const label = `Theme: ${palette.name}. Change theme`;
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger asChild>
        <button className="btn btn-quiet btn-icon" type="button" aria-label={label} title={label}>{ICON}</button>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content className="menu theme-menu" align="end" sideOffset={6}>
          <DropdownMenu.RadioGroup value={palette.id} onValueChange={choose}>
            {PALETTES.map(p => (
              <DropdownMenu.RadioItem key={p.id} value={p.id} className="menu-item theme-item">
                <Swatch palette={p} />
                <span className="theme-text">
                  <span className="menu-title">{p.name}</span>
                  <span className="menu-sub">{p.note}</span>
                </span>
                <DropdownMenu.ItemIndicator className="theme-check" aria-hidden="true">✓</DropdownMenu.ItemIndicator>
              </DropdownMenu.RadioItem>
            ))}
          </DropdownMenu.RadioGroup>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}
