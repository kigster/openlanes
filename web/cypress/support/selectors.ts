// Selectors more than one spec needs.

/**
 * The page's modal dialogs (Radix, class `start`): Stop Local Workers, help, the idea dialog. Not a bare
 * `[role="dialog"]`, which also matches the copilot: a non-modal dialog that stays in the DOM, hidden, while it is
 * minimised, so "the dialog closed" would never come true and `within` would find two.
 */
export const MODAL = '[role="dialog"].start';

/** A lane's Documents dropdown trigger (plan 070), and the document modal it opens. */
export const LANE_DOCUMENTS = 'button[aria-label^="Plan Management of "]';
/** The menu's Documents section; its Actions follow under a divider. */
export const DOCUMENT_ITEMS = '[role="group"][aria-label="Documents"] [role="menuitem"]';
export const DOCUMENT_MODAL = ".document-modal";
