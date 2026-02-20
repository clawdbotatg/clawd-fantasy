"use client";

import { useEffect, useState } from "react";

export const CountdownTimer = ({ endTime }: { endTime: bigint }) => {
  const [now, setNow] = useState(Math.floor(Date.now() / 1000));

  useEffect(() => {
    const interval = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(interval);
  }, []);

  const end = Number(endTime);
  const remaining = end - now;

  if (remaining <= 0) {
    return <span className="text-[#FF4136] font-bold">Ended</span>;
  }

  const days = Math.floor(remaining / 86400);
  const hours = Math.floor((remaining % 86400) / 3600);
  const minutes = Math.floor((remaining % 3600) / 60);
  const seconds = remaining % 60;

  return (
    <span className="font-mono text-sm">
      {days > 0 && `${days}d `}
      {hours.toString().padStart(2, "0")}:{minutes.toString().padStart(2, "0")}:{seconds.toString().padStart(2, "0")}
    </span>
  );
};
