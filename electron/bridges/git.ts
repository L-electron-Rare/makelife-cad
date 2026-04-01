import git from 'isomorphic-git'
import fs from 'fs'
import http from 'isomorphic-git/http/node'

export async function gitStatus(dir: string) {
  const matrix = await git.statusMatrix({ fs, dir })
  return matrix
    .filter(([, head, workdir, stage]) => !(head === 1 && workdir === 1 && stage === 1))
    .map(([filepath, head, workdir, stage]) => ({
      filepath,
      status: head === 0 && workdir === 2 ? 'new' :
              head === 1 && workdir === 2 ? 'modified' :
              head === 1 && workdir === 0 ? 'deleted' : 'unknown',
    }))
}

export async function gitLog(dir: string, depth = 20) {
  const commits = await git.log({ fs, dir, depth })
  return commits.map(c => ({
    oid: c.oid,
    message: c.commit.message,
    author: { name: c.commit.author.name, email: c.commit.author.email, timestamp: c.commit.author.timestamp },
  }))
}

export async function gitAdd(dir: string, filepath: string) {
  await git.add({ fs, dir, filepath })
}

export async function gitCommit(dir: string, message: string, author: { name: string; email: string }) {
  return git.commit({ fs, dir, message, author })
}

export async function gitBranches(dir: string) {
  return git.listBranches({ fs, dir })
}

export async function gitCurrentBranch(dir: string) {
  return git.currentBranch({ fs, dir }) as Promise<string | undefined>
}
