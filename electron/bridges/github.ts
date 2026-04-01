import { Octokit } from '@octokit/rest'

let octokit: Octokit | null = null

export function initGitHub(token: string) { octokit = new Octokit({ auth: token }) }

function ok(): Octokit { if (!octokit) throw new Error('GitHub not authenticated'); return octokit }

export async function listIssues(owner: string, repo: string, state: 'open' | 'closed' | 'all' = 'open') {
  return (await ok().issues.listForRepo({ owner, repo, state, per_page: 100 })).data
}

export async function createIssue(owner: string, repo: string, title: string, body?: string) {
  return (await ok().issues.create({ owner, repo, title, body })).data
}

export async function updateIssue(owner: string, repo: string, issue_number: number, update: object) {
  return (await ok().issues.update({ owner, repo, issue_number, ...update })).data
}

export async function listPRs(owner: string, repo: string, state: 'open' | 'closed' | 'all' = 'open') {
  return (await ok().pulls.list({ owner, repo, state, per_page: 50 })).data
}

export async function listWorkflowRuns(owner: string, repo: string) {
  return (await ok().actions.listWorkflowRunsForRepo({ owner, repo, per_page: 20 })).data.workflow_runs
}
