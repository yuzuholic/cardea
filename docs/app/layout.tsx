import type { Metadata } from 'next';
import { appName } from '@/lib/shared';
import { Provider } from '@/components/provider';
import './global.css';

export const metadata: Metadata = {
  title: { template: `%s | ${appName}`, default: appName },
};

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="flex flex-col min-h-screen">
        <Provider>{children}</Provider>
      </body>
    </html>
  );
}
