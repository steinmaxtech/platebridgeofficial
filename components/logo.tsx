export function Logo({ className = "w-10 h-10" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 100 100"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
    >
      <rect width="100" height="100" rx="22" fill="#0A84FF" />
      {/* P letter */}
      <path
        d="M18 20 H42 C52 20 58 26 58 36 C58 46 52 52 42 52 H30 V78 H18 V20 Z M30 31 V41 H42 C45 41 47 39 47 36 C47 33 45 31 42 31 H30 Z"
        fill="white"
      />
      {/* B letter */}
      <path
        d="M50 20 H74 C82 20 86 24 86 31 C86 35.5 84 38.5 80 40 C84.5 41.5 87 45 87 50 C87 58 82 62 73 62 H50 V20 Z M62 31 V36 H72 C74.5 36 76 35 76 33.5 C76 32 74.5 31 72 31 H62 Z M62 47 V51 H73 C75.5 51 77 50 77 49 C77 48 75.5 47 73 47 H62 Z"
        fill="white"
      />
    </svg>
  );
}

export function LogoIcon({ className = "w-10 h-10" }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 100 100"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
    >
      <rect width="100" height="100" rx="22" fill="#0A84FF" />
      {/* P letter */}
      <path
        d="M18 20 H42 C52 20 58 26 58 36 C58 46 52 52 42 52 H30 V78 H18 V20 Z M30 31 V41 H42 C45 41 47 39 47 36 C47 33 45 31 42 31 H30 Z"
        fill="white"
      />
      {/* B letter */}
      <path
        d="M50 20 H74 C82 20 86 24 86 31 C86 35.5 84 38.5 80 40 C84.5 41.5 87 45 87 50 C87 58 82 62 73 62 H50 V20 Z M62 31 V36 H72 C74.5 36 76 35 76 33.5 C76 32 74.5 31 72 31 H62 Z M62 47 V51 H73 C75.5 51 77 50 77 49 C77 48 75.5 47 73 47 H62 Z"
        fill="white"
      />
    </svg>
  );
}
