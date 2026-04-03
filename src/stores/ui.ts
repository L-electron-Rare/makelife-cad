import { create } from 'zustand'

type Page = 'dashboard' | 'explorer' | 'freecad' | 'git' | 'ci' | 'ai' | 'firmware' | 'settings'

interface UIState {
  activePage: Page
  sidebarCollapsed: boolean
  setActivePage: (page: Page) => void
  toggleSidebar: () => void
}

export const useUIStore = create<UIState>((set) => ({
  activePage: 'dashboard',
  sidebarCollapsed: false,
  setActivePage: (page) => set({ activePage: page }),
  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),
}))
