import { Octokit } from '@octokit/rest'

let client: Octokit | null = null

export function initGitHub(token: string) {
  client = new Octokit({ auth: token })
  return { ok: true }
}

function ensureClient(): Octokit {
  if (!client) throw new Error('GitHub client not initialised; call github:init first')
  return client
}

export async function listIssues(owner: string, repo: string, state: 'open' | 'closed' | 'all' = 'open') {
  const gh = ensureClient()
  const { data } = await gh.issues.listForRepo({ owner, repo, state, per_page: 50 })
  return data
}

export async function createIssue(owner: string, repo: string, title: string, body: string) {
  const gh = ensureClient()
  const { data } = await gh.issues.create({ owner, repo, title, body })
  return data
}

export async function updateIssue(owner: string, repo: string, issue_number: number, update: Record<string, unknown>) {
  const gh = ensureClient()
  const { data } = await gh.issues.update({ owner, repo, issue_number, ...update })
  return data
}

export async function listPRs(owner: string, repo: string, state: 'open' | 'closed' | 'all' = 'open') {
  const gh = ensureClient()
  const { data } = await gh.pulls.list({ owner, repo, state, per_page: 50 })
  return data
}

export async function listWorkflowRuns(owner: string, repo: string) {
  const gh = ensureClient()
  const { data } = await gh.actions.listWorkflowRunsForRepo({ owner, repo, per_page: 50 })
  return data
}
