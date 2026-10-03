"use client";

import { useState } from "react";

/**
 * A person's photo in the round avatar, or their initials when there is no
 * photo — or when the photo will not load, so a missing file never shows as a
 * broken-image icon.
 */
export function UserAvatar({ src, initials, className = "" }: { src?: string | null; initials: string; className?: string }) {
  const [failed, setFailed] = useState<string | null>(null);
  const show = !!src && failed !== src;

  return (
    <span className={`app-avatar${show ? " has-photo" : ""}${className ? ` ${className}` : ""}`} aria-hidden="true">
      {show
        // eslint-disable-next-line @next/next/no-img-element -- user uploads on the API's own host, or a local preview blob
        ? <img src={src} alt="" onError={() => setFailed(src)} />
        : initials}
    </span>
  );
}
