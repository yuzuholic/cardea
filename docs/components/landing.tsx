import Link from 'next/link';
import { Icon } from '@/components/icons';
import { PageCards, type Page } from '@/components/page-cards';

const HERO_LINKS = [
  { title: 'Installation', detail: 'What install.sh does, and how to re-run it', href: '/docs/install' },
  { title: 'Claude Code', detail: 'What Cardea owns and what it leaves alone', href: '/docs/claude-code' },
];

const PAGES: Page[] = [
  { title: 'Skills', summary: 'What each skill does', detail: 'Every skill the Cardea plugin ships, and the skills it installs from elsewhere.', href: '/docs/skills', icon: 'skills' },
  { title: 'Agents', summary: 'Orchestrator and implementers', detail: 'Who starts each agent, its model and effort, and how a batch of tasks runs.', href: '/docs/agents', icon: 'agents' },
  { title: 'MCP', summary: 'Registered servers', detail: 'What each MCP server is for, and whether it runs locally or on the NAS.', href: '/docs/mcp', icon: 'mcp' },
  { title: 'Stack', summary: 'Tools, NAS and decisions', detail: 'Every tool and its pinned version, the NAS services and why each choice was made.', href: '/docs/stack', icon: 'stack' },
  { title: 'Verification', summary: 'Tests, and how CI runs them', detail: 'What each test checks and what it needs.', href: '/docs/tests', icon: 'tests' },
];

function MoreLink({ href, children }: { href: string; children: string }) {
  return (
    <Link href={href} className="inline-flex items-center gap-0.5 font-medium text-fd-primary hover:underline">
      {children}
      <Icon name="chevron" size={16} />
    </Link>
  );
}

export function Landing() {
  return (
    <main className="mx-auto w-full max-w-[1200px] flex-1 px-4 pb-16 md:px-12">
      <h1 className="pt-10 text-5xl font-bold tracking-tight md:pt-12">Cardea</h1>
      <p className="mt-3 max-w-2xl text-lg text-fd-muted-foreground">
        One command installs my agentic coding setup: Claude Code, its MCP servers and plugins, and the services they talk to on the NAS.
      </p>

      <div className="mt-8 grid gap-10 lg:grid-cols-[1.6fr_1fr] lg:gap-16">
        <section
          data-hero
          className="relative flex min-h-56 flex-col justify-between rounded-3xl p-7 text-white shadow-[0_18px_50px_-12px_rgb(74_63_196/0.55)]"
        >
          <p className="text-4xl font-bold tracking-tight">Agentic coding</p>
          <ul className="mt-6 space-y-2.5">
            {HERO_LINKS.map((link) => (
              <li key={link.href}>
                <Link href={link.href} className="group block">
                  <span className="inline-flex items-center gap-0.5 text-lg font-semibold group-hover:underline">
                    {link.title}
                    <Icon name="chevron" size={20} />
                  </span>
                  <span className="block text-[15px] text-white">{link.detail}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>

        <div className="space-y-6 lg:border-s lg:border-fd-border lg:ps-10">
          <section>
            <h2 className="text-xl font-semibold">Start here</h2>
            <p className="mb-1 mt-1 text-[15px] text-fd-muted-foreground">
              A run brings the machine in line with the repo, and is safe to repeat.
            </p>
            <MoreLink href="/docs/install">Read the installation guide</MoreLink>
          </section>
          <section>
            <h2 className="text-xl font-semibold">Decisions</h2>
            <p className="mb-1 mt-1 text-[15px] text-fd-muted-foreground">
              Why each tool was kept or dropped.
            </p>
            <MoreLink href="/docs/decisions">Read the decisions</MoreLink>
          </section>
        </div>
      </div>

      <h2 className="mb-4 mt-10 text-2xl font-semibold tracking-tight">More</h2>
      <PageCards pages={PAGES} />
    </main>
  );
}
