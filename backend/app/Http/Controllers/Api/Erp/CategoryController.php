<?php

namespace App\Http\Controllers\Api\Erp;

use App\Http\Controllers\Controller;
use App\Models\Erp\Product;
use App\Models\Erp\ProductCategory;
use App\Services\AuditLogger;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class CategoryController extends Controller
{
    public function __construct(private readonly TenantContext $tenant, private readonly AuditLogger $audit) {}

    public function index(): JsonResponse
    {
        $counts = Product::query()->selectRaw('category_id, COUNT(*) AS c')->groupBy('category_id')->pluck('c', 'category_id');

        return response()->json(['data' => ProductCategory::query()->orderBy('name')->get()
            ->each(fn ($c) => $c->setAttribute('products_count', (int) ($counts[$c->id] ?? 0)))]);
    }

    public function store(Request $request): JsonResponse
    {
        $category = ProductCategory::create($this->rules($request));
        $this->audit->log('category.created', "Added category {$category->name}", $category);

        return response()->json(['data' => $category], 201);
    }

    public function update(Request $request, ProductCategory $category): JsonResponse
    {
        $data = $this->rules($request, $category->id);
        abort_if(($data['parent_id'] ?? null) === $category->id, 422, 'A category cannot sit inside itself.');
        $category->update($data);
        $this->audit->log('category.updated', "Updated category {$category->name}", $category);

        return response()->json(['data' => $category]);
    }

    public function destroy(ProductCategory $category): JsonResponse
    {
        // Products keep their records; they simply become uncategorised.
        Product::withTrashed()->where('category_id', $category->id)->update(['category_id' => null]);
        $category->delete();
        $this->audit->log('category.deleted', "Deleted category {$category->name}", $category);

        return response()->json(['message' => "{$category->name} deleted."]);
    }

    private function rules(Request $request, ?int $ignore = null): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:120', Rule::unique('product_categories')->where('company_id', $this->tenant->id())->ignore($ignore)],
            'parent_id' => ['nullable', 'integer', Rule::exists('product_categories', 'id')->where('company_id', $this->tenant->id())],
        ]);
    }
}
