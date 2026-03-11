import { type Ref, ref } from "vue"

function toggleInSet(source: Ref<Set<string>>, value: string) {
    const next = new Set(source.value)
    if (next.has(value)) next.delete(value)
    else next.add(value)
    source.value = next
}

export function useFilter(initialPlatforms: Set<string>, initialLanguages: Set<string>) {
    const allPlatforms = ref<string[]>([])
    const allLanguages = ref<string[]>([])

    const selectedPlatforms = ref<Set<string>>(initialPlatforms)
    const selectedLanguages = ref<Set<string>>(initialLanguages)

    function togglePlatform(value: string) {
        toggleInSet(selectedPlatforms, value)
    }

    function toggleLanguage(value: string) {
        toggleInSet(selectedLanguages, value)
    }

    function clearPlatforms() {
        selectedPlatforms.value = new Set()
    }

    function clearLanguages() {
        selectedLanguages.value = new Set()
    }

    return {
        allPlatforms,
        allLanguages,
        selectedPlatforms,
        selectedLanguages,
        togglePlatform,
        toggleLanguage,
        clearPlatforms,
        clearLanguages,
    }
}
