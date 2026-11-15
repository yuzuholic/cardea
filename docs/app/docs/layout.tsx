import { source } from '@/lib/source';
import { DocsLayout } from 'fumadocs-ui/layouts/docs';
import { HomeLayout } from 'fumadocs-ui/layouts/home';
import { baseOptions } from '@/lib/layout.shared';
import { getTabs } from '@/lib/tabs';
import { PageTabs } from '@/components/page-tabs';

export default function Layout({ children }: LayoutProps<'/docs'>) {
  return (
    <HomeLayout {...baseOptions()}>
      <PageTabs {...getTabs()} />
      <DocsLayout
        tree={source.getPageTree()}
        nav={{ enabled: false }}
        sidebar={{ enabled: false }}
        containerProps={{ style: { '--fd-banner-height': '6.75rem' } as React.CSSProperties }}
      >
        {children}
      </DocsLayout>
    </HomeLayout>
  );
}
