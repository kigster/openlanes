import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClientProvider } from "@tanstack/react-query";
import "./index.css";
import App from "./App.tsx";
import { createQueryClient } from "./api/queryClient";
import favicon from "./assets/favicon.png";
import { restorePalette } from "./shell/usePalette";

// Before the first render, so the page never flashes the wrong colours.
restorePalette();

// The favicon is docs/logos/square-239x239.png converted to sRGB, bundled like the header's logo.
const icon = document.querySelector<HTMLLinkElement>("link[rel~='icon']") ?? document.head.appendChild(document.createElement("link"));
icon.rel = "icon";
icon.type = "image/png";
icon.href = favicon;

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={createQueryClient()}>
      <App />
    </QueryClientProvider>
  </StrictMode>,
);
