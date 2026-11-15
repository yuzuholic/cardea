import Link from 'next/link';
import { Icon, type IconName } from '@/components/icons';

export type Page = { title: string; summary: string; detail: string; href: string; icon: IconName };

export function PageCards({ pages }: { pages: Page[] }) {
  return (
    <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-6">
      {pages.map((page, i) => (
        <Link
          key={page.href}
          href={page.href}
          className={`group flex ${i < 3 ? 'lg:col-span-2' : 'lg:col-span-3'} flex-col overflow-hidden rounded-xl bg-fd-card shadow-lg shadow-black/10 transition-transform duration-200 hover:-translate-y-0.5 dark:shadow-black/40`}
        >
          <div className="flex items-center gap-3 bg-fd-foreground/[0.05] p-4">
            <span className="grid size-9 shrink-0 place-items-center rounded-[10px] bg-linear-to-b from-[#3d8bff] to-[#2f6fe0] text-white">
              <Icon name={page.icon} />
            </span>
            <div className="min-w-0 flex-1">
              <p className="font-semibold leading-tight">{page.title}</p>
              <p className="text-sm leading-snug text-fd-muted-foreground">{page.summary}</p>
            </div>
            <span className="text-fd-primary transition-transform group-hover:translate-x-0.5">
              <Icon name="chevron" size={22} />
            </span>
          </div>
          <p className="p-4 text-[15px] leading-snug text-fd-muted-foreground">{page.detail}</p>
        </Link>
      ))}
    </div>
  );
}
