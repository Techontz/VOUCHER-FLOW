<?php

use App\Http\Controllers\Api\Erp\Crm;
use App\Http\Controllers\Api\Erp\Documents;
use Illuminate\Support\Facades\Route;

/*
| CRM and document management. Required inside the authenticated, tenant
| scoped /api/erp group. Which leads, deals and documents a person sees is
| narrowed again inside the controllers (own records, shared documents).
*/

Route::middleware('module:crm')->prefix('crm')->group(function () {
    Route::middleware('permission:crm.view')->group(function () {
        Route::get('overview', [Crm\CrmOverviewController::class, 'overview']);
        Route::get('forecast', [Crm\CrmOverviewController::class, 'forecast']);
        Route::get('win-loss', [Crm\CrmOverviewController::class, 'winLoss']);
        Route::get('people', [Crm\CrmOverviewController::class, 'people']);
        Route::get('leads', [Crm\LeadController::class, 'index']);
        Route::get('leads/regions', [Crm\LeadController::class, 'regions']);
        Route::get('leads/{lead}', [Crm\LeadController::class, 'show']);
        Route::get('opportunities', [Crm\OpportunityController::class, 'index']);
        Route::get('opportunities/board', [Crm\OpportunityController::class, 'board']);
        Route::get('opportunities/{opportunity}', [Crm\OpportunityController::class, 'show']);
        Route::get('activities', [Crm\ActivityController::class, 'index']);
    });

    Route::middleware(['permission:crm.view', 'permission:crm.manage'])->group(function () {
        Route::post('leads', [Crm\LeadController::class, 'store']);
        Route::put('leads/{lead}', [Crm\LeadController::class, 'update']);
        Route::post('leads/{lead}/convert', [Crm\LeadController::class, 'convert']);
        Route::post('opportunities', [Crm\OpportunityController::class, 'store']);
        Route::put('opportunities/{opportunity}', [Crm\OpportunityController::class, 'update']);
        Route::post('opportunities/{opportunity}/stage', [Crm\OpportunityController::class, 'stage']);
        Route::post('activities', [Crm\ActivityController::class, 'store']);
        Route::put('activities/{activity}', [Crm\ActivityController::class, 'update']);
        Route::post('activities/{activity}/complete', [Crm\ActivityController::class, 'complete']);
        Route::post('activities/{activity}/reopen', [Crm\ActivityController::class, 'reopen']);
        Route::delete('activities/{activity}', [Crm\ActivityController::class, 'destroy']);
    });

    Route::middleware(['permission:crm.view', 'permission:crm.assign'])->group(function () {
        Route::post('leads/{lead}/assign', [Crm\LeadController::class, 'assign']);
        Route::post('opportunities/{opportunity}/assign', [Crm\OpportunityController::class, 'assign']);
    });
});

Route::middleware('module:documents')->prefix('files')->group(function () {
    Route::middleware('permission:documents.view')->group(function () {
        Route::get('folders', [Documents\FolderController::class, 'index']);
        Route::get('browse', [Documents\FolderController::class, 'browse']);
        Route::get('documents', [Documents\DocumentController::class, 'index']);
        Route::get('expiring', [Documents\DocumentController::class, 'expiring']);
        Route::get('linked', [Documents\DocumentController::class, 'linked']);
        Route::get('documents/{document}', [Documents\DocumentController::class, 'show']);
        Route::get('documents/{document}/download', [Documents\DocumentController::class, 'download']);
    });

    Route::middleware(['permission:documents.view', 'permission:documents.upload'])->group(function () {
        Route::post('documents', [Documents\DocumentController::class, 'store']);
        Route::put('documents/{document}', [Documents\DocumentController::class, 'update']);
        Route::post('documents/{document}/versions', [Documents\DocumentController::class, 'addVersion']);
        Route::post('documents/{document}/links', [Documents\DocumentController::class, 'addLink']);
        Route::delete('documents/{document}/links/{link}', [Documents\DocumentController::class, 'removeLink']);
    });

    Route::delete('documents/{document}', [Documents\DocumentController::class, 'destroy'])->middleware('permission:documents.delete');

    Route::middleware('permission:documents.manage')->group(function () {
        Route::get('people', [Documents\FolderController::class, 'people']);
        Route::post('folders', [Documents\FolderController::class, 'store']);
        Route::put('folders/{folder}', [Documents\FolderController::class, 'update']);
        Route::delete('folders/{folder}', [Documents\FolderController::class, 'destroy']);
        Route::post('documents/{document}/retention', [Documents\DocumentController::class, 'retention']);
        Route::post('documents/{document}/restore', [Documents\DocumentController::class, 'restore'])->withTrashed();
    });
});
