"use client";

type Entry = {
  player: string;
  picks: string[];
  claimed: boolean;
};

const truncAddr = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`;

export const PlayerList = ({ entries, winners }: { entries: Entry[]; winners?: string[] }) => {
  const winnerSet = new Set((winners || []).map(w => w.toLowerCase()));

  return (
    <div className="space-y-2">
      {entries.length === 0 && <p className="text-sm opacity-50">No players yet</p>}
      {entries.map((entry, i) => {
        const isWinner = winnerSet.has(entry.player.toLowerCase());
        return (
          <div
            key={i}
            className={`p-3 rounded-lg border ${
              isWinner ? "border-[#FFD700] bg-[#FFD700]/10" : "border-base-300 bg-base-200"
            }`}
          >
            <div className="flex items-center gap-2 mb-1">
              {isWinner && <span className="text-[#FFD700]">🏆</span>}
              <span className="font-mono text-sm">{truncAddr(entry.player)}</span>
              {entry.claimed && <span className="badge badge-sm badge-success">Claimed</span>}
            </div>
            <div className="pl-6 space-y-0.5">
              {entry.picks.map((pick, j) => (
                <div key={j} className="text-xs opacity-70 flex items-center gap-1">
                  <span>Pick {j + 1}:</span>
                  <span className="font-mono">{truncAddr(pick)}</span>
                </div>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
};
