// The settings page's channel for the nav menu: a pick opens that pane and scrolls to it.
import { revealer, scrollWhenThere } from "../shell/reveal";
import { paneAnchor } from "./model";

export const { reveal: revealPane, takePending: takePendingReveal, onReveal } = revealer("settings", id => scrollWhenThere(paneAnchor(id)));
