'use client';

import { useEffect, useRef } from 'react';
import Link from 'next/link';
import { animate, stagger } from 'animejs';

export type Page = { title: string; summary: string; href: string };

// the landing grid, after heuresis: cards fade up in turn and lift on hover.
export function PageCards({ pages, startDelay = 0 }: { pages: Page[]; startDelay?: number }) {
  const grid = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!grid.current) return;
    animate(grid.current.querySelectorAll('[data-card]'), {
      opacity: [0, 1],
      translateY: [12, 0],
      delay: stagger(70, { start: startDelay }),
      duration: 450,
      ease: 'outCubic',
    });
  }, [startDelay]);

  return (
    <div ref={grid} className="grid gap-4 sm:grid-cols-2">
      {pages.map((page) => (
        <Link key={page.href} href={page.href} data-card className="group block opacity-0">
          <div className="h-full rounded-xl border bg-fd-card p-4 transition-all duration-200 group-hover:-translate-y-0.5 group-hover:border-eva-green/50 group-hover:bg-fd-muted/60 group-hover:shadow-md">
            <div className="flex items-center justify-between gap-3">
              <p className="font-medium">{page.title}</p>
              <span
                aria-hidden
                className="text-fd-muted-foreground transition-all duration-200 group-hover:-translate-y-0.5 group-hover:translate-x-0.5 group-hover:text-eva-green"
              >
                ↗
              </span>
            </div>
            <p className="mt-1 text-sm text-fd-muted-foreground">{page.summary}</p>
          </div>
        </Link>
      ))}
    </div>
  );
}
