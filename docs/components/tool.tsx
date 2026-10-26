import type { ReactNode } from 'react';
import { basePath } from '@/lib/shared';

// a tool name with its logo from public/icons. one-colour marks are drawn as a mask so they
// take the text colour in both themes; full-colour logos are shown as they are.
export function Tool({ icon, mono = false, children }: { icon: string; mono?: boolean; children: ReactNode }) {
  const src = `${basePath}/icons/${icon}`;
  return (
    <span className="inline-flex items-center gap-2 align-middle">
      {mono ? (
        <span aria-hidden className="size-4 shrink-0 bg-current" style={{ mask: `url(${src}) center / contain no-repeat` }} />
      ) : (
        <img src={src} alt="" width={16} height={16} className="!m-0 size-4 shrink-0 rounded-sm object-contain" />
      )}
      {children}
    </span>
  );
}
