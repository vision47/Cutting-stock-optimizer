from fastapi import FastAPI
from pydantic import BaseModel
from typing import List
from collections import defaultdict
from pulp import *
import uvicorn

app = FastAPI()

# Define input schema
class PipeItem(BaseModel):
    id: str
    length: int
    quantity: int

class OptimizationInput(BaseModel):
    multiplier: int
    stock_length: int
    items: List[PipeItem]

@app.post("/optimize")
def optimize_cut(input_data: OptimizationInput):
    stock_len = input_data.stock_length
    multiplier = input_data.multiplier

    # Step 1: Adjust oversize and apply multiplier
    adjusted = []
    for item in input_data.items:
        qty = item.quantity * multiplier
        if item.length > stock_len:
            full = item.length // stock_len
            rem = item.length % stock_len
            if full > 0:
                adjusted.append(("{}_full".format(item.id), stock_len, qty * full))
            if rem > 0:
                adjusted.append(("{}_rem".format(item.id), rem, qty))
        else:
            adjusted.append((item.id, item.length, qty))

    # Step 2: Merge identical lengths
    merged = defaultdict(int)
    for _, length, qty in adjusted:
        merged[length] += qty

    demand = sorted(merged.items())
    unique_lengths = [l for l, _ in demand]

    # Step 3: Create simple greedy patterns
    all_lengths = sorted([l for l, q in demand for _ in range(q)], reverse=True)
    patterns = []
    while all_lengths:
        total, cut = 0, []
        for l in all_lengths[:]:
            if total + l <= stock_len:
                total += l
                cut.append(l)
                all_lengths.remove(l)
        patterns.append(cut)

    # Step 4: Build pattern matrix
    matrix = []
    for pat in patterns:
        row = [pat.count(l) for l in unique_lengths]
        matrix.append(row)

    # Step 5: Solve with PuLP
    model = LpProblem("CuttingStock", LpMinimize)
    x = [LpVariable(f"x_{i}", 0, None, LpInteger) for i in range(len(matrix))]
    model += lpSum(x)
    for i, (_, qty) in enumerate(demand):
        model += lpSum(x[j] * matrix[j][i] for j in range(len(matrix))) >= qty
    model.solve()

    # Step 6: Collect result
    result = []
    for i, var in enumerate(x):
        if var.varValue and var.varValue > 0:
            result.append({
                "pattern": patterns[i],
                "usage_count": int(var.varValue),
                "used": sum(patterns[i]),
                "scrap": stock_len - sum(patterns[i])
            })

    return {
        "stock_used": int(value(model.objective)),
        "patterns": result
    }

# Optional: local testing
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
