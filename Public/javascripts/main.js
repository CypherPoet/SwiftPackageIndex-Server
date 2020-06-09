import { ExternalLinkRetargeter } from './external_link_retargeter.js'
import { SPISearchCore } from './search_core.js'
import { SPISearchKeyboardNavigation } from './search_keyboard_navigation.js'
import { SPICopyPackageURL } from './copy_package_url.js'

window.externalLinkRetargeter = new ExternalLinkRetargeter()
window.spiSearchCore = new SPISearchCore()
window.spiSearchKeyboardNavigation = new SPISearchKeyboardNavigation()
window.spiCopyPackageURL = new SPICopyPackageURL()
