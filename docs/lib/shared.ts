export const appName = 'Cardea';
export const docsRoute = '/docs';

// github pages serves the site under /<repo>; the workflow sets this, local dev leaves it empty.
export const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? '';

export const gitConfig = {
  user: 'yuzuholic',
  repo: 'cardea',
  branch: 'main',
};
