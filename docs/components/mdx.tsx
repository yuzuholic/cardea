import defaultMdxComponents from 'fumadocs-ui/mdx';
import type { MDXComponents } from 'mdx/types';
import { DecisionsTable } from '@/components/decisions-table';
import { Tool } from '@/components/tool';

export function getMDXComponents(components?: MDXComponents) {
  return {
    ...defaultMdxComponents,
    DecisionsTable,
    Tool,
    ...components,
  } satisfies MDXComponents;
}

export const useMDXComponents = getMDXComponents;

declare global {
  type MDXProvidedComponents = ReturnType<typeof getMDXComponents>;
}
