import { HomeLayout } from 'fumadocs-ui/layouts/home';
import { baseOptions } from '@/lib/layout.shared';
import { getTabs } from '@/lib/tabs';
import { PageTabs } from '@/components/page-tabs';

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <HomeLayout {...baseOptions()}>
      <PageTabs {...getTabs()} />
      {children}
    </HomeLayout>
  );
}
