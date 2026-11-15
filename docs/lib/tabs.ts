import { source } from '@/lib/source';

// grouped pages keep their flat URLs; this maps each to the tab it sits under
const PARENT: Record<string, string> = {
  '/docs/blind-port': '/docs/agents',
  '/docs/nas': '/docs/stack',
  '/docs/decisions': '/docs/stack',
};

// what a parent page is called in its own second row, so it doesn't repeat the tab above
const OWN_LABEL: Record<string, string> = { '/docs/agents': 'Overview', '/docs/stack': 'Tools' };

export function getTabs() {
  const pages = source.getPageTree().children.flatMap((node) =>
    node.type === 'page' && typeof node.name === 'string' ? [{ name: node.name, url: node.url }] : [],
  );
  const tabs = pages.filter((page) => !PARENT[page.url]);
  const subs: Record<string, typeof pages> = {};

  for (const page of pages) {
    const parent = PARENT[page.url];
    if (parent) {
      subs[parent] ??= [{ ...tabs.find((tab) => tab.url === parent)!, name: OWN_LABEL[parent] }];
      subs[parent].push(page);
    }
  }

  return { tabs, parents: PARENT, subs };
}
