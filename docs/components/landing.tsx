'use client';

import { useEffect, useRef } from 'react';
import { animate } from 'animejs';
import { LandscapeBanner } from '@/components/landscape-banner';
import { PageCards, type Page } from '@/components/page-cards';

const PAGES: Page[] = [
  { title: 'Install', summary: 'What the script does, step by step', href: '/docs/install' },
  { title: 'Claude Code', summary: 'What Cardea owns, and what it leaves alone', href: '/docs/claude-code' },
  { title: 'Stack', summary: 'Every tool and its pinned version', href: '/docs/stack' },
  { title: 'NAS', summary: 'Services, ports, secrets and backups', href: '/docs/nas' },
  { title: 'Decisions', summary: 'Why the stack looks like this', href: '/docs/decisions' },
];

export function Landing() {
  const banner = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!banner.current) return;
    const still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    animate(banner.current, { opacity: [0, 1], ...(still ? {} : { scale: [1.02, 1] }), duration: 700, ease: 'outCubic' });
  }, []);

  return (
    <div className="dot-grid flex-1 overflow-x-clip">
      <div className="mx-auto max-w-5xl space-y-8 px-6 pb-16">
        <section className="space-y-6">
          {/* full-bleed: break out of the centred column to the viewport edges */}
          <div
            ref={banner}
            className="relative left-1/2 h-[380px] w-screen -translate-x-1/2 overflow-hidden opacity-0 sm:h-[440px]"
          >
            <LandscapeBanner />
          </div>
          <div className="space-y-1">
            <p className="text-xs font-medium uppercase tracking-widest text-fd-primary">
              Agentic coding setup
            </p>
            <p className="max-w-2xl text-fd-muted-foreground">
              One command installs Claude Code, its MCP servers and plugins, and the services it
              talks to on the NAS.
            </p>
          </div>
        </section>

        <PageCards pages={PAGES} startDelay={250} />
      </div>
    </div>
  );
}
