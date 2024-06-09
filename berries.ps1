function Get-AllItems {
  param(
    [cmdletbinding()]
    [Parameter(Mandatory=$true, Position=0)]
    [string]$StartingUrl
  )
  $response = Invoke-RestMethod -Uri $StartingUrl
  [System.Collections.ArrayList]$items = $response.results

  $nextUrl = $response.next
  while (-not [string]::IsNullOrEmpty($nextUrl)){
    $response = Invoke-RestMethod -Uri $nextUrl
    $items.AddRange($response.results)
    $nextUrl = $response.next
  }

  return $items

}

function Get-BerryData {
  [cmdletbinding(DefaultParameterSetName='Url')]
  param(
    [Parameter(ParameterSetName='Url', Mandatory=$true, Position=0)]
    [string]$Url,

    [Parameter(ParameterSetName='Name', Mandatory=$true, Position=0)]
    [string]$name
  )
  switch($PSCmdlet.ParameterSetName){
    'Url' {
      $response = Invoke-RestMethod -Uri $Url
    }
    'Name' {
      $response = Invoke-RestMethod -Uri "https://pokeapi.co/api/v2/berry/$name"
    }
  }
  $item = $response.item
  $itemResponse = Invoke-RestMethod -Uri $item.url
  $pokemonsHoldingBerry = $itemResponse.held_by_pokemon
  $pokemons = [System.Collections.ArrayList]::new()
  foreach ($pokemon in $pokemonsHoldingBerry){
    $pokemonResponse = Get-PokemonData -Url $pokemon.pokemon.url
    $pokemons.Add($pokemonResponse) > $null
  }
  
  $result = $response |  Select-Object -Property name, firmness, flavors, natural_gift_power, natural_gift_type, item, @{N="pokemonsHoldingBerry"; E={$pokemons}}
  return $result
}

function Get-BerryVitalDataList{
  $berries = Get-AllItems -StartingUrl "https://pokeapi.co/api/v2/berry"
  $berriesVital = [System.Collections.ArrayList]::new()
  foreach($berry in $berries){
    $berryData = Get-BerryData -Url $berry.url
    $berriesVital.Add($berryData) > $null
  }
  return $berriesVital
}

function Get-ContestTypeData {
  [cmdletbinding(DefaultParameterSetName='Url')]
  param(
    [Parameter(ParameterSetName='Url', Mandatory=$true, Position=0)]
    [string]$Url,

    [Parameter(ParameterSetName='Name', Mandatory=$true, Position=0)]
    [string]$name
  )
  switch($PSCmdlet.ParameterSetName){
    'Url' {
      $response = Invoke-RestMethod -Uri $Url
    }
    'Name' {
      $response = Invoke-RestMethod -Uri "https://pokeapi.co/api/v2/contest-type/$name"
    }
  }
  $result = $response |  Select-Object -Property name, berry_flavor
  return $result
}

function Get-ContestVitalDataList{
  $contestTypes = Get-AllItems -StartingUrl "https://pokeapi.co/api/v2/contest-type"
  $contestTypesVital = [System.Collections.ArrayList]::new()
  foreach($contestType in $contestTypes){
    $contestTypeData = Get-ContestTypeData -Url $contestType.url
    $contestTypesVital.Add($contestTypeData) > $null
  }
  return $contestTypesVital
}

function Group-BerriesByContestType{
  $berries = Get-BerryVitalDataList
  $contestTypes = Get-ContestVitalDataList
  $result = @{}
  foreach($contestType in $contestTypes){
    [string]$berry_flavor = $contestType.berry_flavor.name.Trim()
    $result[$berry_flavor] = [System.Collections.ArrayList]::new()
  }

  foreach($berry in $berries){
    [string]$berry_best_flavor = ($berry.flavors | Sort-Object -Descending potency)[0].flavor.name.Trim()
    $result[$berry_best_flavor].Add($berry) > $null
  }

  return $result
}

function Sort-BerriesInContestsTypeGroups{
  $groupedBerries = Group-BerriesByContestType
  $newGroupedBerries = @{}

  foreach($entry in $groupedBerries.GetEnumerator()){
    $flavor = $entry.Key
    $group = $entry.Value

    # Condition for sorting but no pokemons holding berries.
    $group = $group | Select-Object -Property *, @{N="Potency_total"; E={$_.flavors | Select-Object -ExpandProperty potency | Measure-Object -Sum | Select-Object Sum}}| Sort-Object -Property Potency_total, natural_gift_power, natural_gift_type, pokemonsHoldingBerry -Descending | Select-Object -ExcludeProperty Potency_total
    $newGroupedBerries[$flavor] = $group
  }
  return $newGroupedBerries
}


function Get-PokemonData{
  [cmdletbinding(DefaultParameterSetName='Url')]
  param(
    [Parameter(ParameterSetName='Url', Mandatory=$true, Position=0)]
    [string]$Url,

    [Parameter(ParameterSetName='Name', Mandatory=$true, Position=0)]
    [string]$name
  )
  switch($PSCmdlet.ParameterSetName){
    'Url' {
      $response = Invoke-RestMethod -Uri $Url
    }
    'Name' {
      $response = Invoke-RestMethod -Uri "https://pokeapi.co/api/v2/pokemon/$name"
    }
  }
  $result = $response |  Select-Object -Property *, @{N="base_stats"; E={$_.stats | Select-Object -Property base_stat, @{N="stat_name"; E={$_.stat.name}}}} -ExcludeProperty stats
  return $result
}

function Write-PokemonsHoldingBerry{
  param(
    [Parameter(Mandatory=$true)]
    [System.Collections.ArrayList]$PokemonsHoldingBerry
  )
  foreach($pokemon in $PokemonsHoldingBerry){
    Write-Output "Pokemon Name: $($pokemon.name)"
    Write-Output "Base Stats:"
    $pokemon.base_stats | Format-Table -AutoSize
  }
}

function Write-Summary {
  $contestTypes = Sort-BerriesInContestsTypeGroups
  foreach($contestType in $contestTypes.getEnumerator()){
    $contest = $contestType.Key
    $berries = $contestType.Value | Select-Object -First 3
    Write-Output "--------------------------------"
    Write-Output "Contest Type: $contest"
    foreach($berry in $berries){
      $summaryItem = [ordered]@{
        "Berry Name" = $berry.name
        "Berry Firmness" = $berry.firmness.name
        "Berry Flavors" = ($berry.flavors | Sort-Object -Descending potency)[0].flavor.name
        "Natural Gift Power" = $berry.natural_gift_power
        "Natural Gift Type" = $berry.natural_gift_type.name
      }
      $summaryItem | Format-Table -AutoSize
      Write-Output "Pokemons Holding Berry:"
      if([string]::IsNullOrEmpty($berry.PokemonsHoldingBerry)){
        Write-Output "No Pokemons Holding Berry"
      }else{
        Write-PokemonsHoldingBerry $berry.PokemonsHoldingBerry
      }
    }
  }
}

Write-Summary
