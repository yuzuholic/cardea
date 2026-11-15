'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

export type Tab = { name: string; url: string };

const BAR = 'bg-fd-background';

function Row({ tabs, current, small, label }: { tabs: Tab[]; current: string; small?: boolean; label: string }) {
  const list = useRef<HTMLUListElement>(null);
  const [more, setMore] = useState(false);

  useEffect(() => {
    const el = list.current;
    if (!el) return;

    const update = () => setMore(el.scrollLeft + el.clientWidth < el.scrollWidth - 1);
    el.querySelector('[aria-current]')?.scrollIntoView({ inline: 'center', block: 'nearest' });
    update();
    el.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update);

    return () => {
      el.removeEventListener('scroll', update);
      window.removeEventListener('resize', update);
    };
  }, [current]);

  return (
    <nav aria-label={label}>
      <div className="relative mx-auto w-full max-w-[1200px] px-4 md:px-12">
        <div className={small ? '' : 'border-b border-fd-border'}>
          <ul ref={list} className={`flex gap-2 overflow-x-auto md:gap-6 [scrollbar-width:none] ${small ? 'h-11 items-center' : '-mx-2 -mb-px'}`}>
            {tabs.map((tab) => {
              const active = current === tab.url.replace(/\/$/, '');

              return (
                <li key={tab.url} className="shrink-0">
                  <Link
                    href={tab.url}
                    data-ring-fill
                    aria-current={active ? 'page' : undefined}
                    className={`block rounded-lg transition-colors ${small ? '' : 'px-2'} focus-visible:text-fd-primary ${
                      small ? 'text-sm' : 'text-[15px]'
                    } ${active ? 'font-medium text-fd-foreground' : 'text-fd-muted-foreground hover:text-fd-foreground'}`}
                  >
                    {small ? (
                      <span className={`block rounded-full px-2.5 py-1 ${active ? 'bg-fd-foreground/10' : ''}`}>{tab.name}</span>
                    ) : (
                      <span className={`block border-b-2 py-3.5 ${active ? 'border-fd-foreground' : 'border-transparent'}`}>
                        {tab.name}
                      </span>
                    )}
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
        {more && (
          <div
            aria-hidden
            className="pointer-events-none absolute inset-y-0 right-4 w-12 bg-linear-to-l from-fd-background to-transparent md:hidden"
          />
        )}
      </div>
    </nav>
  );
}

export function PageTabs({
  tabs,
  parents,
  subs,
}: {
  tabs: Tab[];
  parents: Record<string, string>;
  subs: Record<string, Tab[]>;
}) {
  const pathname = usePathname().replace(/\/$/, '') || '/';
  const current = pathname === '/' ? '/docs' : pathname;
  const top = parents[current] ?? current;
  const sub = subs[top];

  return (
    <>
      <div className={`sticky top-14 z-30 ${BAR}`}>
        <Row tabs={tabs} current={top} label="Pages" />
      </div>
      {sub && (
        <div data-sub-row className="z-30 bg-fd-background md:sticky md:top-[6.75rem]">
          <Row tabs={sub} current={current} small label="Section" />
        </div>
      )}
    </>
  );
}
