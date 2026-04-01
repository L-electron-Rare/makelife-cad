import { create } from 'zustand'

interface ProjectState {
  projectPath: string | null
  projectName: string | null
  setProject: (path: string, name: string) => void
  closeProject: () => void
}

export const useProjectStore = create<ProjectState>((set) => ({
  projectPath: null,
  projectName: null,
  setProject: (path, name) => set({ projectPath: path, projectName: name }),
  closeProject: () => set({ projectPath: null, projectName: null }),
}))
