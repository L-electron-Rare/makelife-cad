import fs from 'fs'
import * as git from 'isomorphic-git'

export async function gitStatus(dir: string) {
  return git.statusMatrix({ fs, dir })
}

export async function gitLog(dir: string, depth = 20) {
  return git.log({ fs, dir, depth })
}

export async function gitAdd(dir: string, filepath: string) {
  await git.add({ fs, dir, filepath })
  return { ok: true }
}

export async function gitCommit(dir: string, message: string, author?: { name?: string; email?: string }) {
  const sha = await git.commit({ fs, dir, message, author })
  return { sha }
}

export async function gitBranches(dir: string) {
  return git.listBranches({ fs, dir })
}

export async function gitCurrentBranch(dir: string) {
  return git.currentBranch({ fs, dir, fullname: false })
}
