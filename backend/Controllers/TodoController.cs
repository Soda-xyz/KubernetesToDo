using Microsoft.AspNetCore.Mvc;
using KubernetesToDo.Api.Models;
using KubernetesToDo.Api.Services;

namespace KubernetesToDo.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TodoController : ControllerBase
{
    private readonly TodoService _service;

    public TodoController(TodoService service)
    {
        _service = service;
    }

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var items = await _service.GetAsync();
        return Ok(items);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> Get(string id)
    {
        var item = await _service.GetAsync(id);
        if (item is null) return NotFound();
        return Ok(item);
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] TodoItem item)
    {
        var created = await _service.CreateAsync(item);
        return CreatedAtAction(nameof(Get), new { id = created.Id }, created);
    }

    [HttpPut("{id}")]
    public async Task<IActionResult> Update(string id, [FromBody] TodoItem item)
    {
        item.Id = id; // ensure id matches
        var ok = await _service.UpdateAsync(id, item);
        if (!ok) return NotFound();
        return NoContent();
    }

    [HttpPatch("{id}/complete")]
    public async Task<IActionResult> MarkComplete(string id, [FromBody] PatchCompleteDto dto)
    {
        var ok = await _service.MarkCompleteAsync(id, dto.IsCompleted);
        if (!ok) return NotFound();
        return NoContent();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(string id)
    {
        var ok = await _service.RemoveAsync(id);
        if (!ok) return NotFound();
        return NoContent();
    }

    public class PatchCompleteDto { public bool IsCompleted { get; set; } }
}
