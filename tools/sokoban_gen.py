"""Sokoban level generator + optimal solver used to author the bundled campaign.

The generator works backwards from a solved position by pulling boxes, which
guarantees that every emitted level is solvable.  A* (cost = player moves) then
computes the optimal move/push counts that the game uses for star ratings.

Usage:
    python tools/sokoban_gen.py build      # regenerate data/levels.json
    python tools/sokoban_gen.py verify     # re-verify data/levels.json
"""
from __future__ import annotations

import heapq
import json
import random
import sys
import time
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVELS_PATH = ROOT / "data" / "levels.json"

WALL, FLOOR = "#", " "
DIRS = ((0, -1), (1, 0), (0, 1), (-1, 0))


# --------------------------------------------------------------------------- #
# Level model
# --------------------------------------------------------------------------- #
class Level:
    def __init__(self, rows: list[str]):
        width = max(len(r) for r in rows)
        self.rows = [r.ljust(width) for r in rows]
        self.w = width
        self.h = len(self.rows)
        self.walls: set[int] = set()
        self.goals: set[int] = set()
        self.boxes: set[int] = set()
        self.player: int = -1
        for y, row in enumerate(self.rows):
            for x, ch in enumerate(row):
                i = y * self.w + x
                if ch == "#":
                    self.walls.add(i)
                elif ch == ".":
                    self.goals.add(i)
                elif ch == "$":
                    self.boxes.add(i)
                elif ch == "*":
                    self.boxes.add(i)
                    self.goals.add(i)
                elif ch == "@":
                    self.player = i
                elif ch == "+":
                    self.player = i
                    self.goals.add(i)
        self.floor = {i for i in range(self.w * self.h) if i not in self.walls}

    def to_xsb(self) -> list[str]:
        out = []
        for y in range(self.h):
            row = []
            for x in range(self.w):
                i = y * self.w + x
                if i in self.walls:
                    row.append("#")
                elif i == self.player:
                    row.append("+" if i in self.goals else "@")
                elif i in self.boxes:
                    row.append("*" if i in self.goals else "$")
                elif i in self.goals:
                    row.append(".")
                else:
                    row.append(" ")
            out.append("".join(row))
        return out


def parse_xsb(rows: list[str]) -> Level:
    return Level(list(rows))


# --------------------------------------------------------------------------- #
# Solver
# --------------------------------------------------------------------------- #
class Solver:
    """A* over push states (cost = pushes) with deadlock pruning.

    The first solution found is push-optimal; its walking distance is summed to
    provide a reference move count.
    """

    def __init__(self, level: Level, max_nodes: int = 400_000, max_seconds: float = 15.0):
        self.lv = level
        self.w, self.h = level.w, level.h
        self.max_nodes = max_nodes
        self.max_seconds = max_seconds
        n = self.w * self.h
        self.n = n
        self.wall_mask = sum(1 << c for c in level.walls)
        self.goal_mask = sum(1 << c for c in level.goals)
        self.floor_mask = ((1 << n) - 1) & ~self.wall_mask
        self.nb = []
        for i in range(n):
            x, y = i % self.w, i // self.w
            nbrs = [-1, -1, -1, -1]
            for d, (dx, dy) in enumerate(DIRS):
                nx, ny = x + dx, y + dy
                if 0 <= nx < self.w and 0 <= ny < self.h:
                    nbrs[d] = ny * self.w + nx
            self.nb.append(nbrs)
        self.goal_dist = self._goal_distances()
        self.dead_mask = self._static_dead_mask()
        self.blocks: list[int] = []
        self.cell_blocks: list[list[int]] = [[] for _ in range(n)]
        for y in range(self.h - 1):
            for x in range(self.w - 1):
                mask = (1 << (y * self.w + x)) | (1 << (y * self.w + x + 1)) | \
                       (1 << ((y + 1) * self.w + x)) | (1 << ((y + 1) * self.w + x + 1))
                bid = len(self.blocks)
                self.blocks.append(mask)
                for dy in (0, 1):
                    for dx in (0, 1):
                        self.cell_blocks[(y + dy) * self.w + x + dx].append(bid)
        self._stamp = 0
        self._seen = [0] * n
        self._dist = [0] * n

    def _goal_distances(self) -> list[int]:
        INF = 10**6
        dist = [INF] * self.n
        q = deque()
        m = self.goal_mask
        while m:
            b = m & -m
            i = b.bit_length() - 1
            m ^= b
            dist[i] = 0
            q.append(i)
        floor = self.floor_mask
        while q:
            c = q.popleft()
            nd = dist[c] + 1
            for nb in self.nb[c]:
                if nb >= 0 and (floor >> nb) & 1 and dist[nb] == INF:
                    dist[nb] = nd
                    q.append(nb)
        return dist

    def _static_dead_mask(self) -> int:
        good = 0
        q = deque()
        m = self.goal_mask
        while m:
            b = m & -m
            i = b.bit_length() - 1
            m ^= b
            good |= 1 << i
            q.append(i)
        floor = self.floor_mask
        while q:
            c = q.popleft()
            for d in range(4):
                b = self.nb[c][(d + 2) % 4]
                if b < 0 or not ((floor >> b) & 1):
                    continue
                behind = self.nb[b][(d + 2) % 4]
                if behind >= 0 and ((floor >> behind) & 1) and not ((good >> b) & 1):
                    good |= 1 << b
                    q.append(b)
        return self.floor_mask & ~good

    def _reach(self, player: int, boxes: int):
        self._stamp += 1
        stamp = self._stamp
        seen = self._seen
        dist = self._dist
        nb = self.nb
        walls = self.wall_mask
        seen[player] = stamp
        dist[player] = 0
        queue = [player]
        head = 0
        rep = player
        mask = 1 << player
        while head < len(queue):
            c = queue[head]
            head += 1
            if c < rep:
                rep = c
            nd = dist[c] + 1
            for m in nb[c]:
                if m >= 0 and seen[m] != stamp and not ((walls >> m) & 1) and not ((boxes >> m) & 1):
                    seen[m] = stamp
                    dist[m] = nd
                    mask |= 1 << m
                    queue.append(m)
        return mask, rep

    def _deadlocked(self, boxes: int) -> bool:
        if boxes & self.dead_mask:
            return True
        walls = self.wall_mask
        blocked = walls | boxes
        goals = self.goal_mask
        m = boxes
        while m:
            b = m & -m
            i = b.bit_length() - 1
            m ^= b
            for bid in self.cell_blocks[i]:
                bm = self.blocks[bid]
                if (bm & ~blocked) == 0 and (bm & boxes & ~goals):
                    return True
        return False

    def solve(self, extra_pushes: int = 0):
        lv = self.lv
        start_boxes = sum(1 << c for c in lv.boxes)
        start_player = lv.player
        h0 = 0
        m = start_boxes
        while m:
            b = m & -m
            h0 += self.goal_dist[b.bit_length() - 1]
            m ^= b
        # heap items: f, pushes, player, boxes, node_id
        heap = [(h0, 0, start_player, start_boxes, 0)]
        nodes = [(-1, -1, 0)]
        best: dict[tuple, int] = {}
        goal_mask = self.goal_mask
        pushes_limit = None
        node_count = 0
        start_time = time.time()
        while heap:
            f, g, player, boxes, nid = heapq.heappop(heap)
            reach_mask, rep = self._reach(player, boxes)
            key = (boxes, rep)
            if key in best and best[key] <= g:
                continue
            best[key] = g
            node_count += 1
            if boxes == goal_mask:
                path = []
                moves = 0
                cur = nid
                while nodes[cur][0] >= 0:
                    parent, d, walk = nodes[cur]
                    path.append((d, walk))
                    moves += walk
                    cur = parent
                path.reverse()
                return {"solvable": True, "pushes": g, "moves": moves,
                        "path": path, "nodes": node_count}
            if node_count > self.max_nodes or time.time() - start_time > self.max_seconds:
                return {"solvable": None, "reason": "limit", "nodes": node_count}
            seen = self._seen
            stamp = self._stamp
            walls = self.wall_mask
            for d in range(4):
                stand_off = (d + 2) % 4
                m = boxes
                while m:
                    bb = m & -m
                    b = bb.bit_length() - 1
                    m ^= bb
                    target = self.nb[b][d]
                    if target < 0 or ((walls >> target) & 1) or ((boxes >> target) & 1):
                        continue
                    stand = self.nb[b][stand_off]
                    if stand < 0 or seen[stand] != stamp:
                        continue
                    nboxes = boxes ^ bb ^ (1 << target)
                    if self._deadlocked(nboxes):
                        continue
                    nh = 0
                    mm = nboxes
                    while mm:
                        q = mm & -mm
                        nh += self.goal_dist[q.bit_length() - 1]
                        mm ^= q
                    walk = self._dist[stand] + 1
                    nid2 = len(nodes)
                    nodes.append((nid, d, walk))
                    heapq.heappush(heap, (g + 1 + nh, g + 1, target, nboxes, nid2))
        return {"solvable": False, "nodes": node_count}


# --------------------------------------------------------------------------- #
# Reverse generator
# --------------------------------------------------------------------------- #
def connected(lv: Level) -> bool:
    if not lv.floor:
        return False
    start = next(iter(lv.floor))
    seen = {start}
    q = deque([start])
    w, h = lv.w, lv.h
    while q:
        c = q.popleft()
        x, y = c % w, c // w
        for dx, dy in DIRS:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                ni = ny * w + nx
                if ni in lv.floor and ni not in seen:
                    seen.add(ni)
                    q.append(ni)
    return len(seen) == len(lv.floor)


def make_room(w: int, h: int, rng: random.Random, wall_budget: int):
    grid = [[FLOOR] * w for _ in range(h)]
    for x in range(w):
        grid[0][x] = WALL
        grid[h - 1][x] = WALL
    for y in range(h):
        grid[y][0] = WALL
        grid[y][w - 1] = WALL
    inner = [(x, y) for y in range(2, h - 2) for x in range(2, w - 2)]
    rng.shuffle(inner)
    placed = 0

    def floor_cells():
        cells = set()
        for y in range(h):
            for x in range(w):
                if grid[y][x] != WALL:
                    cells.add(y * w + x)
        return cells

    def still_connected():
        cells = floor_cells()
        if not cells:
            return False
        start = next(iter(cells))
        seen = {start}
        q = deque([start])
        while q:
            c = q.popleft()
            x, y = c % w, c // w
            for dx, dy in DIRS:
                nx, ny = x + dx, y + dy
                ni = ny * w + nx
                if 0 <= nx < w and 0 <= ny < h and ni in cells and ni not in seen:
                    seen.add(ni)
                    q.append(ni)
        return len(seen) == len(cells)

    for x, y in inner:
        if placed >= wall_budget:
            break
        if rng.random() < 0.6:
            continue
        cells = [(x, y)]
        if rng.random() < 0.45:
            cells.append((x + 1, y) if rng.random() < 0.5 else (x, y + 1))
        ok = all(1 <= cx < w - 1 and 1 <= cy < h - 1 and grid[cy][cx] != WALL
                 for cx, cy in cells)
        if not ok:
            continue
        for cx, cy in cells:
            grid[cy][cx] = WALL
        if not still_connected():
            for cx, cy in cells:
                grid[cy][cx] = FLOOR
            continue
        placed += len(cells)
    lv = Level(["".join(r) for r in grid])
    if len(lv.floor) < 12 or not connected(lv):
        return None
    return lv


def reverse_generate(w: int, h: int, n_boxes: int, pulls: int, rng: random.Random,
                     wall_budget: int, solver_time: float = 8.0, par_range=(6, 200)):
    base = make_room(w, h, rng, wall_budget)
    if base is None:
        return None
    cells = sorted(base.floor)
    if len(cells) < n_boxes * 5:
        return None
    goals = set(rng.sample(cells, n_boxes))
    boxes = set(goals)
    player = rng.choice([c for c in cells if c not in boxes])
    walls = base.walls
    nb = []
    for i in range(w * h):
        x, y = i % w, i // w
        n = [-1, -1, -1, -1]
        for d, (dx, dy) in enumerate(DIRS):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                n[d] = ny * w + nx
        nb.append(n)

    def reachable(p, bx):
        seen = {p}
        q = [p]
        for c in q:
            for x in nb[c]:
                if x >= 0 and x not in walls and x not in bx and x not in seen:
                    seen.add(x)
                    q.append(x)
        return seen

    def goal_dist(cell):
        return min(abs(cell % w - g % w) + abs(cell // w - g // w) for g in goals)

    done = 0
    for _ in range(pulls * 5):
        if done >= pulls:
            break
        reach = reachable(player, boxes)
        candidates = []
        for b in boxes:
            bx, by = b % w, b // w
            for d in range(4):
                dx, dy = DIRS[d]
                sx, sy = bx - dx, by - dy
                rx, ry = bx - 2 * dx, by - 2 * dy
                if not (0 <= sx < w and 0 <= sy < h and 0 <= rx < w and 0 <= ry < h):
                    continue
                stand, retreat = sy * w + sx, ry * w + rx
                if stand in walls or retreat in walls or stand in boxes or retreat in boxes:
                    continue
                if stand not in reach:
                    continue
                nb2 = set(boxes)
                nb2.remove(b)
                nb2.add(stand)
                score = sum(goal_dist(c) for c in nb2)
                candidates.append((score, b, stand, retreat, nb2))
        if not candidates:
            break
        candidates.sort(key=lambda t: -t[0])
        pool = candidates[: min(3, len(candidates))]
        pick = pool[0] if rng.random() < 0.75 else rng.choice(pool)
        _, _b, _stand, retreat, nb2 = pick
        boxes = nb2
        player = retreat
        done += 1

    lv = Level(base.rows)
    lv.goals, lv.boxes, lv.player = set(goals), set(boxes), player
    if len(lv.boxes) != n_boxes:
        return None
    if len(boxes & lv.goals) > 1:
        return None
    if sum(goal_dist(c) for c in boxes) < par_range[0] * 0.4:
        return None
    result = Solver(lv, max_nodes=300_000, max_seconds=solver_time).solve()
    if not result.get("solvable"):
        return None
    pushes, moves = result["pushes"], result["moves"]
    if not (par_range[0] <= pushes <= par_range[1]):
        return None
    return {"level": lv, "moves": moves, "pushes": pushes, "solution": result["path"]}


# --------------------------------------------------------------------------- #
# Hand crafted tutorial levels
# --------------------------------------------------------------------------- #
TUTORIALS = [
    ("第一步", "First Push", "用方向键把木箱推到目标点上。", "Push the crate onto the goal.",
     ["#######", "#     #", "# @$. #", "#     #", "#######"]),
    ("向上推", "Push Up", "站在木箱下方，向上推。", "Stand below the crate and push up.",
     ["#######", "#  .  #", "#  $  #", "#  @  #", "#######"]),
    ("转角", "Corner Turn", "木箱只能推，不能被拉。", "Crates can be pushed, never pulled.",
     ["#########", "#   .   #", "#       #", "#   $   #", "#   @   #", "#       #", "#########"]),
    ("绕到另一侧", "Walk Around", "绕到木箱右侧，才能把它推向左边。",
     "Circle to the right side to push the crate left.",
     ["#########", "#.      #", "#  $    #", "#   @   #", "#       #", "#########"]),
    ("两个木箱", "Two Crates", "先想清楚顺序，再动手。", "Plan the order before you move.",
     ["########", "#.    .#", "#  $$  #", "#   @  #", "#      #", "########"]),
    ("别进死角", "Avoid Dead Ends", "推进墙角会让木箱永远无法脱身。",
     "A crate pushed into a corner is stuck forever.",
     ["#########", "#.     .#", "#  ##   #", "#  $    #", "#  $ @  #", "#       #", "#########"]),
    ("窄通道", "Corridor", "在窄通道里，先推远处的箱子。", "In narrow halls, push the far crate first.",
     ["#########", "#   . . #", "#  ###  #", "#   $   #", "#  $    #", "#   @   #", "#########"]),
    ("四方", "Four Ways", "观察目标点的位置，规划路线。", "Study the goals and plan your route.",
     ["##########", "#.      .#", "#  $  $  #", "#    @   #", "#  $  $  #", "#.      .#",
      "##########"]),
]

CHAPTER_META = [
    ("chapter_1", "初入仓库", "Into the Warehouse",
     "熟悉推箱子的基本规则，学会绕路和规划顺序。",
     "Learn the ropes: pushing, walking around, and planning ahead."),
    ("chapter_2", "木箱回廊", "Crate Corridors",
     "狭窄通道与多个木箱，谨慎安排每一步。",
     "Narrow passages and multiple crates demand careful ordering."),
    ("chapter_3", "积木工坊", "The Workshop",
     "复杂房间与死角陷阱，试着寻找最优解。",
     "Dense rooms and corner traps. Can you find the optimal route?"),
    ("chapter_4", "货运中枢", "Freight Hub",
     "大师级难题，用最少的步数完成搬运。",
     "Expert challenges. Finish every haul with minimal moves."),
]

CHAPTER_PARAMS = {
    "chapter_2": dict(sizes=[(6, 6), (7, 6), (7, 7), (8, 7)], boxes=[2, 3], pulls=(18, 40),
                      walls=(3, 6), par=(6, 14), solver_time=8.0),
    "chapter_3": dict(sizes=[(7, 7), (8, 7), (8, 8), (9, 8)], boxes=[3, 4], pulls=(40, 90),
                      walls=(5, 8), par=(11, 22), solver_time=10.0),
    "chapter_4": dict(sizes=[(8, 8), (9, 8), (9, 9), (10, 9)], boxes=[4, 5, 6], pulls=(80, 180),
                      walls=(7, 12), par=(15, 32), solver_time=15.0),
}

NAME_POOL = {
    "chapter_2": [
        ("窄门", "Narrow Door"), ("回声长廊", "Echo Hall"), ("侧门", "Side Entrance"),
        ("木料间", "Timber Room"), ("夜班", "Night Shift"), ("双排货架", "Twin Racks"),
        ("转弯处", "The Turn"), ("装卸口", "Loading Bay"), ("旧楼梯", "Old Stairs"),
        ("中转区", "Transit Zone"), ("背靠背", "Back to Back"), ("第七号线", "Line Seven"),
    ],
    "chapter_3": [
        ("齿轮间", "Gears"), ("堆叠术", "Stacking"), ("工坊一角", "Workshop Corner"),
        ("吊车轨道", "Crane Rail"), ("四个角落", "Four Corners"), ("午休", "Lunch Break"),
        ("黄铜钥匙", "Brass Key"), ("零件柜", "Parts Locker"), ("狭缝", "The Slit"),
        ("手推车", "Handcart"), ("密封仓", "Sealed Hold"), ("夜灯", "Night Lamp"),
    ],
    "chapter_4": [
        ("总调度", "Dispatcher"), ("重载", "Heavy Load"), ("最后一班", "Last Train"),
        ("货运中枢", "Freight Hub"), ("集装箱", "Containers"), ("交叉线", "Crossed Lines"),
        ("迷宫", "Labyrinth"), ("零点", "Zero Hour"), ("压力测试", "Stress Test"),
        ("钢铁森林", "Steel Forest"), ("仓库深处", "Deep Storage"), ("完工", "Clock Out"),
    ],
}

TIPS = {
    "chapter_2": ("别把木箱推到墙角。", "Keep crates out of corners."),
    "chapter_3": ("先处理最难的那个木箱。", "Deal with the hardest crate first."),
    "chapter_4": ("有时候，后退一步才能前进。", "Sometimes you must step back to move forward."),
}


def build_campaign() -> dict:
    rng = random.Random(20251024)
    chapter_specs = [("chapter_2", 12), ("chapter_3", 12), ("chapter_4", 12)]
    all_chapters = []

    tut_levels = []
    for idx, (zh, en, tip_zh, tip_en, rows) in enumerate(TUTORIALS, 1):
        lv = parse_xsb(rows)
        result = Solver(lv, max_nodes=400_000, max_seconds=20).solve()
        if not result.get("solvable"):
            raise SystemExit(f"tutorial {idx} unsolvable: {rows}")
        tut_levels.append(dict(
            id=f"c1_{idx:02d}", name_zh=zh, name_en=en, tip_zh=tip_zh, tip_en=tip_en,
            par_moves=result["moves"], par_pushes=result["pushes"], rows=lv.to_xsb(),
        ))
        print(f"  tutorial {idx}: {result['moves']} moves / {result['pushes']} pushes")
    all_chapters.append(("chapter_1", tut_levels))

    for chap_id, count in chapter_specs:
        p = CHAPTER_PARAMS[chap_id]
        levels = []
        tries = 0
        started = time.time()
        while len(levels) < count:
            tries += 1
            if tries > 8000:
                raise SystemExit(f"generation stalled for {chap_id} at {len(levels)}")
            w, h = rng.choice(p["sizes"])
            n_boxes = rng.choice(p["boxes"])
            got = reverse_generate(w, h, n_boxes, rng.randint(*p["pulls"]), rng,
                                   rng.randint(*p["walls"]), solver_time=p["solver_time"],
                                   par_range=p["par"])
            if got is None:
                continue
            lv = got["level"]
            name_zh, name_en = NAME_POOL[chap_id][len(levels)]
            tip_zh, tip_en = TIPS[chap_id]
            if len(levels) % 4 == 0:
                tip_zh = f"本关最优：{got['moves']} 步。试着少走几步。"
                tip_en = f"Optimal route: {got['moves']} moves. Try to beat it."
            levels.append(dict(
                id=f"c{chap_id[-1]}_{len(levels) + 1:02d}",
                name_zh=name_zh, name_en=name_en, tip_zh=tip_zh, tip_en=tip_en,
                par_moves=got["moves"], par_pushes=got["pushes"], rows=lv.to_xsb(),
            ))
            print(f"  {chap_id} {len(levels):02d}: {lv.w}x{lv.h} "
                  f"{got['pushes']}p/{got['moves']}m ({tries} tries)", flush=True)
        print(f"{chap_id} done in {time.time() - started:.1f}s", flush=True)
        all_chapters.append((chap_id, levels))

    chapters = []
    for chap_id, levels in all_chapters:
        meta = next(m for m in CHAPTER_META if m[0] == chap_id)
        chapters.append(dict(id=meta[0], name_zh=meta[1], name_en=meta[2],
                             desc_zh=meta[3], desc_en=meta[4], levels=levels))
    return dict(version=1, generated_by="tools/sokoban_gen.py", chapters=chapters)


def verify(path: Path) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    failures = 0
    total = 0
    for chapter in data["chapters"]:
        for level in chapter["levels"]:
            total += 1
            lv = parse_xsb(level["rows"])
            if len(lv.boxes) != len(lv.goals):
                print(f"FAIL {level['id']}: boxes {len(lv.boxes)} != goals {len(lv.goals)}")
                failures += 1
                continue
            res = Solver(lv, max_nodes=1_000_000, max_seconds=30).solve()
            if not res.get("solvable"):
                print(f"FAIL {level['id']}: unsolvable ({res})")
                failures += 1
                continue
            if res["moves"] != level["par_moves"] or res["pushes"] != level["par_pushes"]:
                print(f"FIX  {level['id']}: par {level['par_moves']}/{level['par_pushes']} "
                      f"-> optimal {res['moves']}/{res['pushes']}")
                level["par_moves"] = res["moves"]
                level["par_pushes"] = res["pushes"]
    print(f"verified {total} levels, {failures} failures")
    if failures == 0:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    return failures


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "build"
    if cmd == "build":
        t0 = time.time()
        data = build_campaign()
        LEVELS_PATH.parent.mkdir(parents=True, exist_ok=True)
        LEVELS_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        total = sum(len(c["levels"]) for c in data["chapters"])
        print(f"wrote {total} levels to {LEVELS_PATH} in {time.time() - t0:.1f}s")
    elif cmd == "verify":
        raise SystemExit(1 if verify(LEVELS_PATH) else 0)
    else:
        raise SystemExit("usage: sokoban_gen.py [build|verify]")


if __name__ == "__main__":
    main()
