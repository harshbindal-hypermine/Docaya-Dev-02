type BrandMarkProps = {
  size?: number
  className?: string
  label?: string
}

export function DocayaMark({ size = 44, className = '', label = '' }: BrandMarkProps) {
  return (
    <img
      className={`d-brand-image d-docaya-mark ${className}`.trim()}
      src={`${import.meta.env.BASE_URL}brand/docaya-welcome.png`}
      width={size}
      height={size}
      alt={label}
      draggable={false}
    />
  )
}

export function DocayaAIMark({ size = 32, className = '', label = '' }: BrandMarkProps) {
  return (
    <img
      className={`d-brand-image d-docaya-ai-mark ${className}`.trim()}
      src={`${import.meta.env.BASE_URL}brand/ask-docaya-mark.png`}
      width={size}
      height={size}
      alt={label}
      draggable={false}
    />
  )
}
