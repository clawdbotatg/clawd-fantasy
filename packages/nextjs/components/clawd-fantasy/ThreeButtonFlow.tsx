"use client";

import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth";

type Props = {
  spender: string;
  amount: bigint;
  onExecute: () => Promise<void>;
  executeLabel: string;
  executePending: boolean;
  disabled?: boolean;
};

export const ThreeButtonFlow = ({ spender, amount, onExecute, executeLabel, executePending, disabled }: Props) => {
  const { address, chain } = useAccount();
  const { targetNetwork } = useTargetNetwork();

  const { data: allowance, isLoading: allowanceLoading } = useScaffoldReadContract({
    contractName: "MockERC20",
    functionName: "allowance",
    args: [address, spender],
  });

  const { writeContractAsync: approveAsync, isMining: approvePending } = useScaffoldWriteContract({
    contractName: "MockERC20",
  });

  const needsSwitch = chain?.id !== targetNetwork.id;
  const needsApproval = !allowanceLoading && allowance !== undefined && allowance < amount;

  if (needsSwitch) {
    return (
      <button className="btn bg-[#FF4136] text-white hover:bg-[#FF4136]/80 w-full" disabled>
        Switch Network to {targetNetwork.name}
      </button>
    );
  }

  if (needsApproval) {
    return (
      <button
        className="btn bg-[#FF4136] text-white hover:bg-[#FF4136]/80 w-full"
        disabled={approvePending || disabled}
        onClick={async () => {
          await approveAsync({
            functionName: "approve",
            args: [spender, amount],
          });
        }}
      >
        {approvePending ? <span className="loading loading-spinner loading-sm" /> : "Approve CLAWD"}
      </button>
    );
  }

  return (
    <button
      className="btn bg-[#FF4136] text-white hover:bg-[#FF4136]/80 w-full"
      disabled={executePending || disabled}
      onClick={onExecute}
    >
      {executePending ? <span className="loading loading-spinner loading-sm" /> : executeLabel}
    </button>
  );
};
